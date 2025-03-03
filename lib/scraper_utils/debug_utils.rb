# frozen_string_literal: true

require "json"

module ScraperUtils
  # Utilities for debugging web scraping processes
  module DebugUtils
    # Logs details of an HTTP request when debug mode is enabled
    #
    # @param method [String] HTTP method (GET, POST, etc.)
    # @param url [String] Request URL
    # @param parameters [Hash, nil] Optional request parameters
    # @param headers [Hash, nil] Optional request headers
    # @param body [Hash, nil] Optional request body
    # @return [void]
    def self.debug_request(method, url, parameters: nil, headers: nil, body: nil)
      return unless ScraperUtils.debug?

      $stderr.flush
      puts
      ScraperUtils::FiberScheduler.log "🔍 #{method.upcase} #{url}"
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
      return unless ScraperUtils.debug?

      $stderr.flush
      puts
      ScraperUtils::FiberScheduler.log "🔍 DEBUG: #{message}"
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
      return unless ScraperUtils.debug?

      $stderr.flush
      puts
      ScraperUtils::FiberScheduler.log "🔍 DEBUG: #{message}"
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
