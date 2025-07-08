# frozen_string_literal: true

require "scraperwiki"
require "cgi"

module ScraperUtils
  # Methods to support specs
  module SpecSupport
    AUSTRALIAN_STATES = %w[ACT NSW NT QLD SA TAS VIC WA].freeze
    STREET_TYPE_PATTERNS = [
      /\bAv(e(nue)?)?\b/i,
      /\bB(oulevard|lvd)\b/i,
      /\b(Circuit|Cct)\b/i,
      /\bCl(ose)?\b/i,
      /\bC(our|r)?t\b/i,
      /\bCircle\b/i,
      /\bChase\b/i,
      /\bCr(es(cent)?)?\b/i,
      /\bDr((ive)?|v)\b/i,
      /\bEnt(rance)?\b/i,
      /\bGr(ove)?\b/i,
      /\bH(ighwa|w)y\b/i,
      /\bLane\b/i,
      /\bLoop\b/i,
      /\bParkway\b/i,
      /\bPl(ace)?\b/i,
      /\bPriv(ate)?\b/i,
      /\bParade\b/i,
      /\bR(oa)?d\b/i,
      /\bRise\b/i,
      /\bSt(reet)?\b/i,
      /\bSquare\b/i,
      /\bTerrace\b/i,
      /\bWay\b/i
    ].freeze

    AUSTRALIAN_POSTCODES = /\b\d{4}\b/.freeze

    def self.fetch_url_with_redirects(url)
      agent = Mechanize.new
      # FIXME - Allow injection of a check to agree to terms if needed to set a cookie and reget the url
      agent.get(url)
    end

    def self.authority_label(results, prefix: '', suffix: '')
      return nil if results.nil?

      authority_labels = results.map { |record| record['authority_label']}.compact.uniq
      return nil if authority_labels.empty?

      raise "Expected one authority_label, not #{authority_labels.inspect}" if authority_labels.size > 1
      "#{prefix}#{authority_labels.first}#{suffix}"
    end

    # Validates enough addresses are geocodable
    # @param results [Array<Hash>] The results from scraping an authority
    # @param percentage [Integer] The min percentage of addresses expected to be geocodable (default:50)
    # @param variation [Integer] The variation allowed in addition to percentage (default:3)
    # @raise RuntimeError if insufficient addresses are geocodable
    def self.validate_addresses_are_geocodable!(results, percentage: 50, variation: 3)
      return nil if results.empty?

      geocodable = results
                     .map { |record| record["address"] }
                     .uniq
                     .count { |text| ScraperUtils::SpecSupport.geocodable? text }
      puts "Found #{geocodable} out of #{results.count} unique geocodable addresses " \
             "(#{(100.0 * geocodable / results.count).round(1)}%)"
      expected = [((percentage.to_f / 100.0) * results.count - variation), 1].max
      raise "Expected at least #{expected} (#{percentage}% - #{variation}) geocodable addresses, got #{geocodable}" unless geocodable >= expected
      geocodable
    end

    # Check if an address is likely to be geocodable by analyzing its format.
    # This is a bit stricter than needed - typically assert >= 75% match
    # @param address [String] The address to check
    # @return [Boolean] True if the address appears to be geocodable.
    def self.geocodable?(address, ignore_case: false)
      return false if address.nil? || address.empty?
      check_address = ignore_case ? address.upcase : address

      # Basic structure check - must have a street type or unit/lot, uppercase suburb or postcode, state
      has_state = AUSTRALIAN_STATES.any? { |state| check_address.end_with?(" #{state}") || check_address.include?(" #{state} ") }
      has_postcode = address.match?(AUSTRALIAN_POSTCODES)

      # Using the pre-compiled patterns
      has_street_type = STREET_TYPE_PATTERNS.any? { |pattern| check_address.match?(pattern) }

      has_unit_or_lot = address.match?(/\b(Unit|Lot:?)\s+\d+/i)

      uppercase_words = address.scan(/\b[A-Z]{2,}\b/)
      has_uppercase_suburb = uppercase_words.any? { |word| !AUSTRALIAN_STATES.include?(word) }

      if ENV["DEBUG"]
        missing = []
        unless has_street_type || has_unit_or_lot
          missing << "street type / unit / lot"
        end
        missing << "postcode/Uppercase suburb" unless has_postcode || has_uppercase_suburb
        missing << "state" unless has_state
        puts "  address: #{address} is not geocodable, missing #{missing.join(', ')}" if missing.any?
      end

      (has_street_type || has_unit_or_lot) && (has_postcode || has_uppercase_suburb) && has_state
    end

    PLACEHOLDERS = [
      /no description/i,
      /not available/i,
      /to be confirmed/i,
      /\btbc\b/i,
      %r{\bn/a\b}i
    ].freeze

    def self.placeholder?(text)
      PLACEHOLDERS.any? { |placeholder| text.to_s.match?(placeholder) }
    end

    # Validates enough descriptions are reasonable
    # @param results [Array<Hash>] The results from scraping an authority
    # @param percentage [Integer] The min percentage of descriptions expected to be reasonable (default:50)
    # @param variation [Integer] The variation allowed in addition to percentage (default:3)
    # @raise RuntimeError if insufficient descriptions are reasonable
    def self.validate_descriptions_are_reasonable!(results, percentage: 50, variation: 3)
      return nil if results.empty?

      descriptions = results
                       .map { |record| record["description"] }
                       .uniq
                       .count do |text|
        selected = ScraperUtils::SpecSupport.reasonable_description? text
        puts "  description: #{text} is not reasonable" if ENV["DEBUG"] && !selected
        selected
      end
      puts "Found #{descriptions} out of #{results.count} unique reasonable descriptions " \
             "(#{(100.0 * descriptions / results.count).round(1)}%)"
      expected = [(percentage.to_f / 100.0) * results.count - variation, 1].max
      raise "Expected at least #{expected} (#{percentage}% - #{variation}) reasonable descriptions, got #{descriptions}" unless descriptions >= expected
      descriptions
    end

    # Check if this looks like a "reasonable" description
    # This is a bit stricter than needed - typically assert >= 75% match
    def self.reasonable_description?(text)
      !placeholder?(text) && text.to_s.split.size >= 3
    end

    # Validates that all records use the expected global info_url and it returns 200
    # @param results [Array<Hash>] The results from scraping an authority
    # @param expected_url [String] The expected global info_url for this authority
    # @raise RuntimeError if records don't use the expected URL or it doesn't return 200
    def self.validate_uses_one_valid_info_url!(results, expected_url, bot_check_expected: false)
      info_urls = results.map { |record| record["info_url"] }.uniq

      unless info_urls.size == 1
        raise "Expected all records to use one info_url '#{expected_url}', found: #{info_urls.size}"
      end
      unless info_urls.first == expected_url
        raise "Expected all records to use global info_url '#{expected_url}', found: #{info_urls.first}"
      end

      puts "Checking the one expected info_url returns 200: #{expected_url}"

      if defined?(VCR)
        VCR.use_cassette("#{authority_label(results, suffix: '_')}one_info_url") do
          page = fetch_url_with_redirects(expected_url)
          validate_page_response(page, bot_check_expected)
        end
      else
        page = fetch_url_with_redirects(expected_url)
        validate_page_response(page, bot_check_expected)
      end
    end

    # Validates that info_urls have expected details (unique URLs with content validation)
    # @param results [Array<Hash>] The results from scraping an authority
    # @param percentage [Integer] The min percentage of detail checks expected to pass (default:75)
    # @param variation [Integer] The variation allowed in addition to percentage (default:3)
    # @raise RuntimeError if insufficient detail checks pass
    def self.validate_info_urls_have_expected_details!(results, percentage: 75, variation: 3, bot_check_expected: false)
      if defined?(VCR)
        VCR.use_cassette("#{authority_label(results, suffix: '_')}info_url_details") do
          check_info_url_details(results, percentage, variation, bot_check_expected)
        end
      else
        check_info_url_details(results, percentage, variation, bot_check_expected)
      end
    end

    # Check if the page response indicates bot protection
    # @param page [Mechanize::Page] The page response to check
    # @return [Boolean] True if bot protection is detected
    def self.bot_protection_detected?(page)
      return true if %w[403 429].include?(page.code)

      return false unless page.body

      body_lower = page.body.downcase

      # Check for common bot protection indicators
      bot_indicators = [
        'recaptcha',
        'cloudflare',
        'are you human',
        'bot detection',
        'security check',
        'verify you are human',
        'access denied',
        'blocked',
        'captcha'
      ]

      bot_indicators.any? { |indicator| body_lower.include?(indicator) }
    end

    # Validate page response, accounting for bot protection
    # @param page [Mechanize::Page] The page response to validate
    # @param bot_check_expected [Boolean] Whether bot protection is acceptable
    # @raise RuntimeError if page response is invalid and bot protection not expected
    def self.validate_page_response(page, bot_check_expected)
      if bot_check_expected && bot_protection_detected?(page)
        puts "  Bot protection detected - accepting as valid response"
        return
      end

      raise "Expected 200 response from the one expected info_url, got #{page.code}" unless page.code == "200"
    end

    private

    def self.check_info_url_details(results, percentage, variation, bot_check_expected)
      count = 0
      failed = 0
      fib_indices = ScraperUtils::MathsUtils.fibonacci_series(results.size - 1).uniq

      fib_indices.each do |index|
        record = results[index]
        info_url = record["info_url"]
        puts "Checking info_url[#{index}]: #{info_url} has the expected reference, address and description..."

        page = fetch_url_with_redirects(info_url)

        if bot_check_expected && bot_protection_detected?(page)
          puts "  Bot protection detected - skipping detailed validation"
          next
        end

        raise "Expected 200 response, got #{page.code}" unless page.code == "200"

        page_body = page.body.dup.force_encoding("UTF-8").gsub(/\s\s+/, " ")

        %w[council_reference address description].each do |attribute|
          count += 1
          expected = CGI.escapeHTML(record[attribute]).gsub(/\s\s+/, " ")
          expected2 = expected.gsub(/(\S+)\s+(\S+)\z/, '\2 \1') # Handle Lismore post-code/state swap

          next if page_body.include?(expected) || page_body.include?(expected2)

          failed += 1
          puts "  Missing: #{expected}"
          puts "    IN: #{page_body}" if ENV['DEBUG']

          min_required = [((percentage.to_f / 100.0) * count - variation), 1].max
          passed = count - failed
          raise "Too many failures: #{passed}/#{count} passed (min required: #{min_required})" if passed < min_required
        end
      end

      puts "#{(100.0 * (count - failed) / count).round(1)}% detail checks passed (#{failed}/#{count} failed)!" if count > 0
    end

  end
end
