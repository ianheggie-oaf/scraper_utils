# frozen_string_literal: true

require "scraper_utils/adaptive_delay"
require "scraper_utils/authority_utils"
require "scraper_utils/data_quality_monitor"
require "scraper_utils/db_utils"
require "scraper_utils/debug_utils"
require "scraper_utils/log_utils"
require "scraper_utils/mechanize_utils"
require "scraper_utils/robots_checker"
require "scraper_utils/version"

# Utilities for planningalerts scrapers
module ScraperUtils
  # Constants for configuration on Morph.io
  AUSTRALIAN_PROXY_ENV_VAR = "MORPH_AUSTRALIAN_PROXY"

  # Enable debug locally, not on morph.io
  DEBUG_ENV_VAR = "DEBUG"

  # Fatal Error
  class Error < StandardError
  end

  # Fatal error with the site - retrying won't help
  class UnprocessableSite < Error
  end

  # Content validation errors that should not be retried for that record,
  # but other records may be processable
  class UnprocessableRecord < Error
  end

  # Check if debug mode is enabled
  #
  # @return [Boolean] Whether debug mode is active
  def self.debug?
    !ENV[DEBUG_ENV_VAR].to_s.empty?
  end

  def self.australian_proxy
    ap = ENV[AUSTRALIAN_PROXY_ENV_VAR].to_s
    ap.empty? ? nil : ap
  end
end
