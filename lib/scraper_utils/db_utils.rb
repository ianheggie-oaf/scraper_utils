# frozen_string_literal: true

require "scraperwiki"

module ScraperUtils
  # Utilities for database operations in scrapers
  module DbUtils
    # Enable in-memory collection mode instead of saving to SQLite
    def self.collect_saves!
      @collected_saves = []
    end

    # Save to disk rather than collect
    def self.save_immediately!
      @collected_saves = nil
    end

    # Get all collected save calls
    # @return [Array<Array>] Array of [primary_key, record] pairs
    def self.collected_saves
      @collected_saves
    end

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
        Date.parse(record[date_field]) unless record[date_field].to_s.empty?
      rescue ArgumentError
        raise ScraperUtils::UnprocessableRecord,
              "Invalid date format for #{date_field}: #{record[date_field].inspect}"
      end

      # Determine primary key based on presence of authority_label
      primary_key = if record.key?("authority_label")
                      %w[authority_label council_reference]
                    else
                      ["council_reference"]
                    end
      if @collected_saves
        @collected_saves << record
      else
        ScraperWiki.save_sqlite(primary_key, record)
        ScraperUtils::DataQualityMonitor.log_saved_record(record)
      end
    end

    # Clean up records older than 30 days and approx once a month vacuum the DB
    def self.cleanup_old_records
      cutoff_date = (Date.today - 30).to_s
      vacuum_cutoff_date = (Date.today - 35).to_s

      stats = ScraperWiki.sqliteexecute(
        "SELECT COUNT(*) as count, MIN(date_scraped) as oldest FROM data WHERE date_scraped < ?",
        [cutoff_date]
      ).first

      deleted_count = stats["count"]
      oldest_date = stats["oldest"]

      return unless deleted_count.positive? || ENV["VACUUM"]

      LogUtils.log "Deleting #{deleted_count} applications scraped between #{oldest_date} and #{cutoff_date}"
      ScraperWiki.sqliteexecute("DELETE FROM data WHERE date_scraped < ?", [cutoff_date])

      return unless rand < 0.03 || (oldest_date && oldest_date < vacuum_cutoff_date) || ENV["VACUUM"]

      LogUtils.log "  Running VACUUM to reclaim space..."
      ScraperWiki.sqliteexecute("VACUUM")
    end
  end
end
