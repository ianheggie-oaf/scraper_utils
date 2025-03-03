# frozen_string_literal: true

require "scraperwiki"

module ScraperUtils
  # Utilities for database operations in scrapers
  module DbUtils
    # Saves a record to the SQLite database with validation and logging
    #
    # @param record [Hash] The record to be saved
    # @raise [ScraperUtils::UnprocessableRecord] If record fails validation
    # @return [void]
    def self.save_record(record)
      # Validate required fields
      required_fields = %w[council_reference address description info_url date_scraped]
      required_fields.each do |field|
        if record[field].to_s.empty?
          raise ScraperUtils::UnprocessableRecord, "Missing required field: #{field}"
        end
      end

      # Validate date formats
      %w[date_scraped date_received on_notice_from on_notice_to].each do |date_field|
        Date.parse(record[date_field]) if record[date_field]
      rescue ArgumentError
        raise ScraperUtils::UnprocessableRecord,
              "Invalid date format for #{date_field}: #{record[date_field]}"
      end

      # Determine primary key based on presence of authority_label
      primary_key = if record.key?("authority_label")
                      %w[authority_label council_reference]
                    else
                      ["council_reference"]
                    end
      ScraperWiki.save_sqlite(primary_key, record)
      ScraperUtils::DataQualityMonitor.log_saved_record(record)
    end
  end
end
