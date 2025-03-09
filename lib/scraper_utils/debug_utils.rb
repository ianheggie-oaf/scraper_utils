# frozen_string_literal: true

require "json"

module ScraperUtils
  # Utilities for debugging web scraping processes
  module DebugUtils
    DEBUG_ENV_VAR = "DEBUG"
    MORPH_DEBUG_ENV_VAR = "MORPH_DEBUG"

    # Debug level constants
    DISABLED_LEVEL = 0
    BASIC_LEVEL = 1
    VERBOSE_LEVEL = 2
    TRACE_LEVEL = 3

    # Get current debug level (0 = disabled, 1 = basic, 2 = verbose, 3 = trace)
    # Checks DEBUG and MORPH_DEBUG env variables
    # @return [Integer] Debug level
    def self.debug_level
      debug = ENV.fetch(DEBUG_ENV_VAR, ENV.fetch(MORPH_DEBUG_ENV_VAR, '0'))
      debug =~ /^\d/ ? debug.to_i : BASIC_LEVEL
    end

    # Check if debug is enabled at specified level or higher
    #
    # @param level [Integer] Minimum debug level to check for
    # @return [Boolean] true if debugging at specified level is enabled
    def self.debug?(level = BASIC_LEVEL)
      debug_level >= level
    end

    # Check if basic debug output or higher is enabled
    # @return [Boolean] true if debugging is enabled
    def self.basic?
      debug?(BASIC_LEVEL)
    end

    # Check if verbose debug output or higher is enabled
    # @return [Boolean] true if verbose debugging is enabled
    def self.verbose?
      debug?(VERBOSE_LEVEL)
    end

    # Check if debug tracing or higher is enabled
    # @return [Boolean] true if debugging is enabled at trace level
    def self.trace?
      debug?(TRACE_LEVEL)
    end


    # Logs details of an HTTP request when debug mode is enabled
    #
    # @param http_method [String] HTTP http_method (GET, POST, etc.)
    # @param url [String] Request URL
    # @param parameters [Hash, nil] Optional request parameters
    # @param headers [Hash, nil] Optional request headers
    # @param body [Hash, nil] Optional request body
    # @return [void]
    def self.debug_request(http_method, url, parameters: nil, headers: nil, body: nil)
      return unless basic?

      puts
      LogUtils.log "🔍 #{http_method.upcase} #{url}"
      puts "Parameters:", JSON.pretty_generate(parameters) if parameters
      puts "Headers:", JSON.pretty_generate(headers) if headers
      puts "Body:", JSON.pretty_generate(body) if body
      $stdout.flush
    end

    # Logs details of a web page when debug mode is enabled
    #
    # @param page [Mechanize::Page] The web page to debug
    # @param message [String] Context or description for the debug output
    # @return [void]
    def self.debug_page(page, message)
      return unless trace?

      puts
      LogUtils.log "🔍 DEBUG: #{message}"
      puts "Current URL: #{page.uri}"
      puts "Page title: #{page.at('title').text.strip}" if page.at("title")
      puts "",
           "Page content:",
           "-" * 40,
           page.body,
           "-" * 40
      $stdout.flush
    end

    # Logs details about a specific page selector when debug mode is enabled
    #
    # @param page [Mechanize::Page] The web page to inspect
    # @param selector [String] CSS selector to look for
    # @param message [String] Context or description for the debug output
    # @return [void]
    def self.debug_selector(page, selector, message)
      return unless trace?

      puts
      LogUtils.log "🔍 DEBUG: #{message}"
      puts "Looking for selector: #{selector}"
      element = page.at(selector)
      if element
        puts "Found element:"
        puts element.to_html
      else
        puts "Element not found in:"
        puts "-" * 40
        puts page.body
        puts "-" * 40
      end
      $stdout.flush
    end
  end
end
