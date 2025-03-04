# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "scraper_utils/version"

Gem::Specification.new do |spec|
  spec.name = "scraper_utils"
  spec.version = ScraperUtils::VERSION
  spec.authors = ["Ian Heggie"]
  spec.email = ["ian@heggie.biz"]
  spec.required_ruby_version = ">= 2.5.1"

  spec.summary = "planningalerts scraper utilities"
  spec.description = "Utilities to help make planningalerts scrapers, " \
    "especially multi authority scrapers, easier to develop, run and debug."
  spec.homepage = "https://github.com/ianheggie-oaf/#{spec.name}"
  spec.license = "MIT"

  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"

    spec.metadata["homepage_uri"] = spec.homepage
    spec.metadata["source_code_uri"] = spec.homepage
    spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/#{spec.name}/#{ScraperUtils::VERSION}"
    spec.metadata["changelog_uri"] = "#{spec.metadata["source_code_uri"]}/blob/main/CHANGELOG.md"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
            "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "mechanize"
  spec.add_dependency "nokogiri"
  spec.add_dependency "sqlite3"
  spec.metadata["rubygems_mfa_required"] = "true"
end
