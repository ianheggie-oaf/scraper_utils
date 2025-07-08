# frozen_string_literal: true

require "scraper_utils/version"

# Public Apis (responsible for requiring their own dependencies)
require "scraper_utils/authority_utils"
require "scraper_utils/data_quality_monitor"
require "scraper_utils/db_utils"
require "scraper_utils/debug_utils"
require "scraper_utils/log_utils"
require "scraper_utils/maths_utils"
require "scraper_utils/spec_support"

# Mechanize utilities
require "scraper_utils/mechanize_utils"

# Utilities for planningalerts scrapers
module ScraperUtils
  # Constants for configuration on Morph.io
  AUSTRALIAN_PROXY_ENV_VAR = "MORPH_AUSTRALIAN_PROXY"

  # Fatal Error
  class Error < StandardError; end

  # Fatal error with the site - retrying won't help
  class UnprocessableSite < Error; end

  # Fatal Error for a record - other records may be processable
  class UnprocessableRecord < Error; end

  def self.australian_proxy
    ap = ENV[AUSTRALIAN_PROXY_ENV_VAR].to_s
    ap.empty? ? nil : ap
  end
end
