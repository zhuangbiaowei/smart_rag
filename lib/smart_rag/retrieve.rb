require 'securerandom'
require 'json'
require 'time'
require 'digest'

module SmartRAG
  # Executes RetrievalPlan and formats the response as EvidencePack.
  class Retrieve
    DEFAULT_TOP_K = 30
    DEFAULT_CANDIDATE_K = 200
    DEFAULT_RRF_K = 60
    DEFAULT_MAX_SNIPPET_CHARS = 800

    def initialize(client)
      @client = client
      @logger = client.logger
    end

    def execute(plan:)
      normalized_plan = normalize_plan(plan)
      validate_plan!(normalized_plan)

      started_at = monotonic_now
      generated_at = Time.now.utc.iso8601
      request_id = normalized_plan[:request_id] || SecureRandom.uuid
      plan_id = SecureRandom.uuid
      warnings = []
      ignored_fields = []
      applied_filters = {}

      candidates, by_mode_stats = gather_candidates(
        normalized_plan,
        warnings: warnings,
        ignored_fields: ignored_fields,
        applied_filters: applied_filters
      )

      aggregated = aggregate_candidates(candidates, normalized_plan)
      selected = apply_budget_and_diversity(aggregated, normalized_plan, ignored_fields)
      evidences = build_evidences(selected, normalized_plan, generated_at)

      took_ms = ((monotonic_now - started_at) * 1000).round
      stats = {
        candidates: candidates.length,
        returned: evidences.length,
        took_ms: took_ms,
        by_mode: by_mode_stats
      }

      explain = {
        fusion: build_fusion_explain(normalized_plan),
        rerank: build_rerank_explain(normalized_plan),
        filters_applied: applied_filters,
        diversity: build_diversity_explain(normalized_plan),
        ignored_fields: ignored_fields.uniq
      }

      pack = {
        version: normalized_plan[:version] || '0.1',
        plan: normalized_plan,
        plan_id: plan_id,
        request_id: request_id,
        generated_at: generated_at,
        evidences: evidences,
        stats: stats,
        explain: explain,
        warnings: warnings.uniq
      }

      log_retrieve(plan: normalized_plan, stats: stats, explain: explain, warnings: warnings)
      pack
    end

    private

    def gather_candidates(plan, warnings:, ignored_fields:, applied_filters:)
      budget = plan[:budget] || {}
      per_mode_k = symbolize_keys(budget[:per_mode_k] || {})
      candidate_k = positive_int(budget[:candidate_k], DEFAULT_CANDIDATE_K)
      by_mode = {}
      candidates = []

      plan[:queries].each_with_index do |query, index|
        query_text = query[:text].to_s.strip
        next if query_text.empty?

        mode = normalize_mode(query[:mode])
        search_type = mode_to_search_type(mode)
        unless search_type
          warnings << "query[#{index}] mode=#{mode} not supported; fallback to hybrid"
          search_type = 'hybrid'
        end

        mode_limit = positive_int(per_mode_k[mode], candidate_k)
        query_weight = query[:weight].to_f
        query_weight = 1.0 if query_weight <= 0.0

        query_filters = symbolize_keys(query[:filters] || {})
        global_filters = symbolize_keys(plan[:global_filters] || {})
        merged_filters = merge_filters(global_filters, query_filters)
        search_options, query_ignored, applied = build_search_options(merged_filters)

        ignored_fields.concat(query_ignored)
        applied_filters.merge!(applied) { |_k, old_v, new_v| merge_filter_values(old_v, new_v) }

        response = @client.search(
          query_text,
          search_options.merge(
            search_type: search_type,
            limit: mode_limit
          )
        )
        results = extract_results(response)

        by_mode[mode] ||= { candidates: 0, returned: 0 }
        by_mode[mode][:candidates] += results.length
        by_mode[mode][:returned] += results.length

        results.each_with_index do |result, rank_index|
          candidate = build_candidate(
            result,
            mode: mode,
            query_text: query_text,
            query_index: index,
            rank_index: rank_index,
            query_weight: query_weight
          )
          next if candidate.nil?
          next unless candidate_passes_filters?(candidate, merged_filters)

          candidates << candidate
        end
      end

      [candidates.compact, by_mode]
    end

    def build_candidate(result, mode:, query_text:, query_index:, rank_index:, query_weight:)
      section = extract_section(result)
      section_id = extract_section_id(result, section)
      document_id = extract_document_id(result, section)
      return nil if section_id.nil? && document_id.nil?

      snippet = extract_snippet(result, section)
      title = extract_title(result, section)
      language = extract_language(result, section)
      source_uri = extract_source_uri(result, section)
      source_type = extract_source_type(source_uri, result)

      vector_score = extract_vector_score(result, mode)
      fts_score = extract_fts_score(result, mode)
      rerank_score = numeric_or_nil(result[:rerank_score])
      rrf_score = query_weight / (DEFAULT_RRF_K + rank_index + 1).to_f

      {
        key: evidence_key(section_id, document_id, snippet),
        id: stable_evidence_id(section_id, document_id, snippet),
        section_id: section_id,
        document_id: document_id,
        title: title,
        snippet: snippet,
        language: language,
        source_uri: source_uri,
        source_type: source_type,
        signals: {
          vector_score: vector_score,
          vector_rank: vector_score ? rank_index + 1 : nil,
          fts_score: fts_score,
          fts_rank: fts_score ? rank_index + 1 : nil,
          rrf_score: rrf_score,
          rerank_score: rerank_score,
          tag_score: 0.0,
          topic_score: 0.0
        },
        provenance: {
          mode: mode,
          query_text: query_text,
          query_index: query_index
        },
        metadata: extract_metadata(result, section),
        raw: {
          content_ref: section_id ? "section:#{section_id}" : nil
        }
      }
    end

    def aggregate_candidates(candidates, plan)
      rerank_enabled = !!plan.dig(:ranking, :rerank, :enabled)
      grouped = {}

      candidates.each do |candidate|
        key = candidate[:key]
        if grouped[key]
          grouped[key][:signals][:rrf_score] += candidate[:signals][:rrf_score].to_f
          grouped[key][:signals][:vector_score] = max_numeric(
            grouped[key][:signals][:vector_score],
            candidate[:signals][:vector_score]
          )
          grouped[key][:signals][:fts_score] = max_numeric(
            grouped[key][:signals][:fts_score],
            candidate[:signals][:fts_score]
          )
          grouped[key][:signals][:rerank_score] = max_numeric(
            grouped[key][:signals][:rerank_score],
            candidate[:signals][:rerank_score]
          )
          grouped[key][:signals][:vector_rank] = min_numeric(
            grouped[key][:signals][:vector_rank],
            candidate[:signals][:vector_rank]
          )
          grouped[key][:signals][:fts_rank] = min_numeric(
            grouped[key][:signals][:fts_rank],
            candidate[:signals][:fts_rank]
          )

          current_best = grouped[key][:final_score]
          incoming_score = score_for_sort(candidate, rerank_enabled)
          if incoming_score > current_best
            grouped[key][:provenance] = candidate[:provenance]
            grouped[key][:snippet] = candidate[:snippet] if candidate[:snippet]
            grouped[key][:metadata] = merge_hash(grouped[key][:metadata], candidate[:metadata])
            grouped[key][:final_score] = incoming_score
          end
        else
          grouped[key] = candidate.dup
          grouped[key][:final_score] = score_for_sort(candidate, rerank_enabled)
        end
      end

      grouped.values
    end

    def apply_budget_and_diversity(candidates, plan, ignored_fields)
      budget = plan[:budget] || {}
      top_k = positive_int(budget[:top_k], DEFAULT_TOP_K)
      candidate_k = positive_int(budget[:candidate_k], DEFAULT_CANDIDATE_K)
      diversity_by_document = positive_int(budget.dig(:diversity, :by_document), nil)
      diversity_by_source = positive_int(budget.dig(:diversity, :by_source), nil)
      diversity_by_section = positive_int(budget.dig(:diversity, :by_section), nil)
      ignored_fields << 'budget.diversity.by_section not supported' if diversity_by_section

      sorted = candidates.sort_by { |item| -item[:final_score].to_f }.first(candidate_k)
      return sorted.first(top_k) if diversity_by_document.nil? && diversity_by_source.nil?

      selected = []
      per_document = Hash.new(0)
      per_source = Hash.new(0)
      sorted.each do |item|
        doc_id = item[:document_id]
        if diversity_by_document && doc_id && per_document[doc_id] >= diversity_by_document
          next
        end

        source_key = item[:source_uri].to_s.strip
        source_key = item[:source_type].to_s if source_key.empty?
        if diversity_by_source && !source_key.empty? && per_source[source_key] >= diversity_by_source
          next
        end

        selected << item
        per_document[doc_id] += 1 if doc_id
        per_source[source_key] += 1 if diversity_by_source && !source_key.empty?
        break if selected.length >= top_k
      end

      if selected.length < top_k
        ignored_fields << 'budget.diversity constraints partially applied due to insufficient diversity in candidates'
      end

      selected
    end

    def build_evidences(selected, plan, generated_at)
      output = plan[:output] || {}
      include_signals = output.fetch(:include_signals, true)
      include_snippets = output.fetch(:include_snippets, true)
      include_provenance = output.fetch(:include_provenance, true)
      include_raw = output.fetch(:include_raw, false)
      max_snippet_chars = positive_int(output[:max_snippet_chars], DEFAULT_MAX_SNIPPET_CHARS)
      snippet_policy = output[:snippet_policy] || 'auto'

      selected.map do |item|
        evidence = {
          id: item[:id],
          kind: 'resource_section',
          document_id: item[:document_id],
          section_id: item[:section_id],
          title: item[:title],
          source_uri: item[:source_uri],
          source_type: item[:source_type],
          snippet_policy: snippet_policy,
          language: item[:language],
          metadata: item[:metadata] || {}
        }

        if include_snippets
          evidence[:snippet] = truncate_text(item[:snippet], max_snippet_chars)
        else
          evidence[:snippet] = ''
        end

        evidence[:signals] = sanitize_signals(item[:signals]) if include_signals

        if include_provenance
          evidence[:provenance] = item[:provenance].merge(retrieved_at: generated_at)
        end

        evidence[:raw] = item[:raw] if include_raw
        evidence
      end
    end

    def build_search_options(filters)
      ignored = []
      applied = {}

      options = {
        include_content: true,
        include_metadata: true
      }

      if filters[:document_ids]
        options[:document_ids] = filters[:document_ids]
        applied[:document_ids] = filters[:document_ids]
      end

      if filters[:tag_ids]
        options[:tag_ids] = filters[:tag_ids]
        applied[:tag_ids] = filters[:tag_ids]
      end

      if filters[:language]
        options[:language] = Array(filters[:language]).first
        applied[:language] = Array(filters[:language])
      end

      if filters[:time_range].is_a?(Hash)
        time_from = filters[:time_range][:from] || filters[:time_range]['from']
        time_to = filters[:time_range][:to] || filters[:time_range]['to']
        options[:date_from] = time_from if time_from
        options[:date_to] = time_to if time_to
        applied[:time_range] = { from: time_from, to: time_to }
      end

      if filters[:source_type]
        applied[:source_type] = Array(filters[:source_type]).map(&:to_s)
      end
      if filters[:source_uri_prefix]
        applied[:source_uri_prefix] = Array(filters[:source_uri_prefix]).map(&:to_s)
      end
      if filters[:topic_ids]
        applied[:topic_ids] = Array(filters[:topic_ids]).map(&:to_i)
      end

      [options, ignored, applied]
    end

    def extract_results(response)
      return [] unless response.is_a?(Hash)

      Array(response[:results] || response['results'])
    end

    def extract_section(result)
      return result[:section] if result.is_a?(Hash) && result[:section]
      return result['section'] if result.is_a?(Hash) && result['section']

      result
    end

    def extract_section_id(result, section)
      return result[:section_id] if result.is_a?(Hash) && result[:section_id]
      return result['section_id'] if result.is_a?(Hash) && result['section_id']
      return section[:id] if section.is_a?(Hash) && section[:id]
      return section['id'] if section.is_a?(Hash) && section['id']
      return section.id if section.respond_to?(:id)

      nil
    end

    def extract_document_id(result, section)
      return result[:document_id] if result.is_a?(Hash) && result[:document_id]
      return result['document_id'] if result.is_a?(Hash) && result['document_id']
      return section[:document_id] if section.is_a?(Hash) && section[:document_id]
      return section['document_id'] if section.is_a?(Hash) && section['document_id']
      return section.document_id if section.respond_to?(:document_id)

      nil
    end

    def extract_snippet(result, section)
      if result.is_a?(Hash)
        return result[:content] if result[:content]
        return result[:highlight] if result[:highlight]
        return result['content'] if result['content']
      end

      if section.is_a?(Hash)
        return section[:content] if section[:content]
        return section['content'] if section['content']
      elsif section.respond_to?(:content)
        return section.content
      end

      ''
    end

    def extract_title(result, section)
      if result.is_a?(Hash)
        return result[:document_title] if result[:document_title]
        return result[:title] if result[:title]
        return result['document_title'] if result['document_title']
      end

      if section.is_a?(Hash)
        return section[:section_title] if section[:section_title]
        return section[:title] if section[:title]
      elsif section.respond_to?(:section_title)
        return section.section_title
      end

      nil
    end

    def extract_language(result, section)
      if result.is_a?(Hash)
        return result[:language] if result[:language]
        return result['language'] if result['language']
      end

      if section.is_a?(Hash)
        return section[:language] if section[:language]
        return section['language'] if section['language']
      elsif section.respond_to?(:language)
        return section.language
      end

      nil
    end

    def extract_source_uri(result, section)
      if result.is_a?(Hash)
        metadata = result[:metadata] || result['metadata']
        if metadata.is_a?(Hash)
          uri = metadata[:source_uri] || metadata['source_uri']
          return uri if uri
        end
        return result[:url] if result[:url]
      end

      if section.respond_to?(:document) && section.document
        return section.document.url if section.document.respond_to?(:url)
      end

      nil
    end

    def extract_source_type(source_uri, result)
      if result.is_a?(Hash)
        metadata = result[:metadata] || result['metadata']
        if metadata.is_a?(Hash)
          source_type = metadata[:source_type] || metadata['source_type']
          return source_type if source_type
        end
      end

      return 'url' if source_uri.to_s.start_with?('http://', 'https://')
      return 'file' if source_uri.to_s.start_with?('file://', '/')

      'manual'
    end

    def candidate_passes_filters?(candidate, filters)
      return true unless filters.is_a?(Hash) && !filters.empty?

      if filters[:source_type]
        allowed = Array(filters[:source_type]).map { |v| v.to_s.downcase }
        actual = candidate[:source_type].to_s.downcase
        return false unless allowed.include?(actual)
      end

      if filters[:source_uri_prefix]
        prefixes = Array(filters[:source_uri_prefix]).map(&:to_s)
        uri = candidate[:source_uri].to_s
        return false unless prefixes.any? { |prefix| uri.start_with?(prefix) }
      end

      if filters[:topic_ids]
        required_topic_ids = Array(filters[:topic_ids]).map(&:to_i).uniq
        section_topics = section_topic_ids_for(candidate[:section_id])
        return false if required_topic_ids.any? && (required_topic_ids & section_topics).empty?
      end

      true
    end

    def section_topic_ids_for(section_id)
      return [] if section_id.nil?
      return [] unless defined?(::SmartRAG) && ::SmartRAG.respond_to?(:db) && ::SmartRAG.db

      @section_topic_cache ||= {}
      return @section_topic_cache[section_id] if @section_topic_cache.key?(section_id)

      topic_ids = ::SmartRAG.db[:research_topic_sections]
                  .where(section_id: section_id)
                  .select_map(:research_topic_id)
                  .map(&:to_i)
      @section_topic_cache[section_id] = topic_ids
    rescue StandardError
      []
    end

    def extract_metadata(result, section)
      metadata = {}
      metadata_from_result = result.is_a?(Hash) ? (result[:metadata] || result['metadata']) : nil
      metadata.merge!(metadata_from_result) if metadata_from_result.is_a?(Hash)

      section_id = extract_section_id(result, section)
      document_id = extract_document_id(result, section)

      metadata[:section_id] ||= section_id if section_id
      metadata[:document_id] ||= document_id if document_id
      metadata
    end

    def extract_vector_score(result, mode)
      return numeric_or_nil(result[:vector_score]) if result.is_a?(Hash) && result.key?(:vector_score)
      return numeric_or_nil(result[:similarity]) if mode == 'semantic' && result.is_a?(Hash) && result.key?(:similarity)
      return numeric_or_nil(result[:boosted_score]) if result.is_a?(Hash) && result.key?(:boosted_score)

      nil
    end

    def extract_fts_score(result, mode)
      return numeric_or_nil(result[:fts_score]) if result.is_a?(Hash) && result.key?(:fts_score)
      return numeric_or_nil(result[:text_score]) if result.is_a?(Hash) && result.key?(:text_score)
      return numeric_or_nil(result[:rank_score]) if mode == 'exact' && result.is_a?(Hash) && result.key?(:rank_score)

      nil
    end

    def sanitize_signals(signals)
      {
        vector_score: signals[:vector_score] || 0.0,
        vector_rank: signals[:vector_rank],
        fts_score: signals[:fts_score] || 0.0,
        fts_rank: signals[:fts_rank],
        rrf_score: signals[:rrf_score] || 0.0,
        rerank_score: signals[:rerank_score],
        tag_score: signals[:tag_score] || 0.0,
        topic_score: signals[:topic_score] || 0.0
      }
    end

    def mode_to_search_type(mode)
      case mode
      when 'exact' then 'fulltext'
      when 'semantic' then 'vector'
      when 'hybrid' then 'hybrid'
      else nil
      end
    end

    def normalize_mode(mode)
      case mode.to_s
      when 'exact', 'semantic', 'hybrid' then mode.to_s
      when 'relational', 'associative' then 'hybrid'
      else 'hybrid'
      end
    end

    def normalize_plan(plan)
      return {} unless plan.is_a?(Hash)

      deep_symbolize(plan)
    end

    def validate_plan!(plan)
      raise ArgumentError, 'Retrieval plan must be a hash' unless plan.is_a?(Hash)
      raise ArgumentError, 'Retrieval plan requires queries' unless plan[:queries].is_a?(Array) && !plan[:queries].empty?
    end

    def deep_symbolize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), memo|
          normalized_key = key.respond_to?(:to_sym) ? key.to_sym : key
          memo[normalized_key] = deep_symbolize(child)
        end
      when Array
        value.map { |item| deep_symbolize(item) }
      else
        value
      end
    end

    def symbolize_keys(value)
      return {} unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, val), memo|
        memo[key.to_sym] = val
      end
    end

    def merge_filters(global_filters, query_filters)
      merged = global_filters.dup
      query_filters.each do |key, value|
        merged[key] = value
      end
      merged
    end

    def merge_filter_values(old_value, new_value)
      old_array = old_value.is_a?(Array) ? old_value : [old_value].compact
      new_array = new_value.is_a?(Array) ? new_value : [new_value].compact
      merged = (old_array + new_array).uniq
      merged.length == 1 ? merged.first : merged
    end

    def merge_hash(base_hash, new_hash)
      return base_hash unless new_hash.is_a?(Hash)

      base_hash.merge(new_hash) { |_key, old_v, new_v| new_v.nil? ? old_v : new_v }
    end

    def build_fusion_explain(plan)
      fusion = plan.dig(:ranking, :fusion) || {}
      {
        method: fusion[:method] || 'rrf',
        rrf_k: fusion[:rrf_k] || DEFAULT_RRF_K,
        weights: fusion[:weights] || { exact: 1.0, semantic: 1.0 }
      }
    end

    def build_rerank_explain(plan)
      rerank = plan.dig(:ranking, :rerank) || {}
      {
        enabled: !!rerank[:enabled],
        model: rerank[:model],
        top_n: rerank[:top_n]
      }
    end

    def build_diversity_explain(plan)
      diversity = plan.dig(:budget, :diversity) || {}
      {
        by_document: diversity[:by_document],
        by_source: diversity[:by_source],
        by_section: diversity[:by_section],
        applied: !diversity.empty?
      }
    end

    def evidence_key(section_id, document_id, snippet)
      return "section:#{section_id}" if section_id
      return "document:#{document_id}:#{snippet.to_s[0, 64]}" if document_id

      "snippet:#{snippet.to_s[0, 64]}"
    end

    def stable_evidence_id(section_id, document_id, snippet)
      return "section:#{section_id}" if section_id

      digest = Digest::SHA1.hexdigest(snippet.to_s)[0, 12]
      return "doc:#{document_id}:#{digest}" if document_id

      "snippet:#{digest}"
    end

    def score_for_sort(candidate, rerank_enabled)
      rerank_score = candidate.dig(:signals, :rerank_score)
      return rerank_score.to_f if rerank_enabled && !rerank_score.nil?

      candidate.dig(:signals, :rrf_score).to_f
    end

    def max_numeric(a, b)
      return b if a.nil?
      return a if b.nil?

      [a.to_f, b.to_f].max
    end

    def min_numeric(a, b)
      return b if a.nil?
      return a if b.nil?

      [a.to_i, b.to_i].min
    end

    def numeric_or_nil(value)
      return nil if value.nil?

      value.to_f
    rescue StandardError
      nil
    end

    def truncate_text(text, max_chars)
      return '' if text.nil?

      str = text.to_s
      return str if max_chars.nil? || max_chars <= 0 || str.length <= max_chars

      str[0, max_chars]
    end

    def positive_int(value, default_value)
      return default_value if value.nil?

      int_value = value.to_i
      return default_value if int_value <= 0

      int_value
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def log_retrieve(plan:, stats:, explain:, warnings:)
      return unless ::SmartRAG.db

      payload = {
        request_id: plan[:request_id],
        version: plan[:version],
        plan_json: plan,
        stats: stats,
        explain: explain,
        warnings: warnings
      }

      ::SmartRAG.db[:search_logs].insert(
        query: "retrieve:#{plan[:purpose] || 'other'}",
        search_type: 'hybrid',
        execution_time_ms: stats[:took_ms],
        results_count: stats[:returned],
        filters: payload.to_json,
        created_at: Sequel::CURRENT_TIMESTAMP
      )
    rescue StandardError => e
      @logger.warn "Failed to log retrieve plan: #{e.message}" if @logger
    end
  end
end
