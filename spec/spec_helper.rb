# frozen_string_literal: true

require "simplecov"
require "simplecov-console"
require "webmock/rspec"

SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"

  # Track files in lib directory
  add_group "Utilities", "lib/scraper_utils"
end

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::Console
  ]
)

require "bundler/setup"
require "rspec"

# Clear ENV variables that affect tests:
%w[MORPH_DAYS MORPH_EVERYTIME MORPH_MAX_PERIOD
   MORPH_EXPECT_BAD MORPH_DISABLE_RANDOM
   MORPH_DISABLE_THREADS  MORPH_MAX_WORKERS MORPH_RUN_TIMEOUT
   MORPH_CLIENT_TIMEOUT MORPH_NOT_COMPLIANT MORPH_RANDOM_DELAY MORPH_MAX_LOAD
   MORPH_DISABLE_SSL_CHECK MORPH_USE_PROXY MORPH_USER_AGENT].each do |var|
  ENV[var] = nil
end

require "scraper_utils"

# Load all support files
Dir[File.expand_path('./support/**/*.rb', __dir__ || "spec/")].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Make it stop on the first failure. Makes in this case
  # for quicker debugging
  config.fail_fast = !ENV["FAIL_FAST"].to_s.empty?

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
