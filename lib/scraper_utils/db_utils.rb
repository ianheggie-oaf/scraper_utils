# frozen_string_literal: true

require "uri"
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
      record = record.transform_keys(&:to_s)
      ScraperUtils::PaValidation.validate_record!(record)

      # Determine the primary key based on the presence of authority_label
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
    def self.cleanup_old_records(force: false)
      cutoff_date = (Date.today - 30).to_s
      vacuum_cutoff_date = (Date.today - 35).to_s

      stats = ScraperWiki.sqliteexecute(
        "SELECT COUNT(*) as count, MIN(date_scraped) as oldest FROM data WHERE date_scraped < ?",
        [cutoff_date]
      ).first

      deleted_count = stats["count"]
      oldest_date = stats["oldest"]

      return unless deleted_count.positive? || ENV["VACUUM"] || force

      LogUtils.log "Deleting #{deleted_count} applications scraped between #{oldest_date} and #{cutoff_date}"
      ScraperWiki.sqliteexecute("DELETE FROM data WHERE date_scraped < ?", [cutoff_date])

      return unless rand < 0.03 || (oldest_date && oldest_date < vacuum_cutoff_date) || ENV["VACUUM"] || force

      LogUtils.log "  Running VACUUM to reclaim space..."
      ScraperWiki.sqliteexecute("VACUUM")
    rescue SqliteMagic::NoSuchTable => e
      ScraperUtils::LogUtils.log "Ignoring: #{e} whilst cleaning old records" if ScraperUtils::DebugUtils.trace?
    end
  end
end
