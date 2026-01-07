lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "smart_rag/version"

Gem::Specification.new do |spec|
  spec.name = "smart_rag"
  spec.version = SmartRAG::VERSION
  spec.authors = ["SmartRAG Team"]
  spec.email = ["team@smartrag.com"]

  spec.summary = "A hybrid RAG (Retrieval-Augmented Generation) system with vector and full-text search"
  spec.description = "SmartRAG provides intelligent document processing, vector embeddings, full-text search, and hybrid retrieval capabilities for enhanced information retrieval and question answering."
  spec.homepage = "https://github.com/smartrag/smartrag"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/smartrag/smartrag"
  spec.metadata["changelog_uri"] = "https://github.com/smartrag/smartrag/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "sequel", "~> 5.0"
  spec.add_dependency "pg", "~> 1.0"
  spec.add_dependency "yaml", "~> 0.2"
  spec.add_dependency "httparty", "~> 0.20"
  spec.add_dependency "nokogiri", "~> 1.0"
  spec.add_dependency "markitdown", "~> 0.1"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 4.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "simplecov", "~> 0.21"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "factory_bot", "~> 6.0"
  spec.add_development_dependency "database_cleaner", "~> 2.0"
end
