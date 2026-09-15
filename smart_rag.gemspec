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
    tracked = `git ls-files -z`.split("\x0")
    runtime = Dir.glob('{lib,db,config,exe}/**/*', File::FNM_DOTMATCH).select { |path| File.file?(path) }
    (tracked + runtime).uniq.reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies (must cover every gem `require`d from lib/)
  spec.add_dependency "sequel", "~> 5.0"
  spec.add_dependency "pg", "~> 1.0"
  spec.add_dependency "rack", ">= 2.2", "< 4"
  spec.add_dependency "puma", ">= 6.0", "< 8"
  spec.add_dependency "aws-sdk-s3", "~> 1.0"
  spec.add_dependency "smart_prompt", "~> 0.5.4"
  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "ostruct", "~> 0.6"
  spec.add_dependency "dotenv", "~> 2.8"

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
