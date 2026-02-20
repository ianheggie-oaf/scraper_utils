# frozen_string_literal: true

require "uri"
require "date"

module ScraperUtils
  # Validates scraper records match Planning Alerts requirements before submission.
  # Use in specs to catch problems early rather than waiting for PA's import.
  module PaValidation
    REQUIRED_FIELDS = %w[council_reference address description date_scraped].freeze

    # Validates a single record (hash with string keys) against PA's rules.
    # @param record [Hash] The record to validate
    # @raise [ScraperUtils::UnprocessableRecord] if there are error messages
    def self.validate_record!(record)
      errors = validate_record(record)
      raise(ScraperUtils::UnprocessableRecord, errors.join("; ")) if errors&.any?
    end

    # Validates a single record (hash with string keys) against PA's rules.
    # @param record [Hash] The record to validate
    # @return [Array<String>, nil] Array of error messages, or nil if valid
    def self.validate_record(record)
      record = record.transform_keys(&:to_s)
      errors = []

      validate_presence(record, errors)
      validate_info_url(record, errors)
      validate_dates(record, errors)

      errors.empty? ? nil : errors
    end

    private

    def self.validate_presence(record, errors)
      REQUIRED_FIELDS.each do |field|
        errors << "#{field} can't be blank" if record[field].to_s.strip.empty?
      end
      errors << "info_url can't be blank" if record["info_url"].to_s.strip.empty?
    end

    def self.validate_info_url(record, errors)
      url = record["info_url"].to_s.strip
      return if url.empty? # already caught by presence check

      begin
        uri = URI.parse(url)
        unless uri.is_a?(URI::HTTP) && uri.host.to_s != ""
          errors << "info_url must be a valid http\/https URL with host"
        end
      rescue URI::InvalidURIError
        errors << "info_url must be a valid http\/https URL"
      end
    end

    def self.validate_dates(record, errors)
      today = Date.today

      date_scraped = parse_date(record["date_scraped"])
      errors << "Invalid date format for date_scraped: #{record["date_scraped"].inspect} is not a valid ISO 8601 date" if record["date_scraped"] && date_scraped.nil?

      date_received = parse_date(record["date_received"])
      if record["date_received"] && date_received.nil?
        errors << "Invalid date format for date_received: #{record["date_received"].inspect} is not a valid ISO 8601 date"
      elsif date_received && date_received.to_date > today
        errors << "Invalid date for date_received: #{record["date_received"].inspect} is in the future"
      end

      %w[on_notice_from on_notice_to].each do |field|
        val = parse_date(record[field])
        errors << "Invalid date format for #{field}: #{record[field].inspect} is not a valid ISO 8601 date" if record[field] && val.nil?
      end
    end

    # Returns a Date if value is already a Date, or parses a YYYY-MM-DD string.
    # Returns nil if unparseable or blank.
    def self.parse_date(value)
      return nil if value.nil? || value == ""
      return value if value.is_a?(Date) || value.is_a?(Time)
      return nil unless value.is_a?(String) && value =~ /\A\d{4}-\d{2}-\d{2}\z/

      Date.parse(value)
    rescue ArgumentError
      nil
    end
  end
end
