# frozen_string_literal: true

require "scraperwiki"

module ScraperUtils
  # Utilities for logging scraper execution details and outcomes
  module LogUtils
    SUMMARY_TABLE = "scrape_summary"
    LOG_TABLE = "scrape_log"
    LOG_RETENTION_DAYS = 30

    # Log details about a scraping run for one or more authorities
    # @param start_time [Time] When this scraping attempt was started
    # @param attempt [Integer] 1 for first run, 2 for first retry, 3 for last retry (without proxy)
    # @param authorities [Array<Symbol>] List of authorities attempted to scrape
    # @param exceptions [Hash{Symbol => Exception}] Any exceptions that occurred during scraping
    # `DataQualityMonitor.stats` is checked for :saved and :unprocessed entries
    # @return [void]
    def self.log_scraping_run(start_time, attempt, authorities, exceptions)
      raise ArgumentError, "Invalid start time" unless start_time.is_a?(Time)
      raise ArgumentError, "Authorities must be a non-empty array" if authorities.empty?

      end_time = Time.now
      duration = (end_time - start_time).round(1)

      successful = []
      failed = []
      interrupted = []

      authorities.each do |authority_label|
        stats = ScraperUtils::DataQualityMonitor.stats&.fetch(authority_label, nil) || {}

        exception = exceptions[authority_label]
        status = if stats[:saved]&.positive?
                   exception ? :interrupted : :successful
                 else
                   :failed
                 end
        case status
        when :successful
          successful << authority_label
        when :interrupted
          interrupted << authority_label
        else
          failed << authority_label
        end

        record = {
          "run_at" => start_time.iso8601,
          "attempt" => attempt,
          "authority_label" => authority_label.to_s,
          "records_saved" => stats[:saved] || 0,
          "unprocessable_records" => stats[:unprocessed] || 0,
          "status" => status.to_s,
          "error_message" => exception&.message,
          "error_class" => exception&.class&.to_s,
          "error_backtrace" => extract_meaningful_backtrace(exception)
        }

        save_log_record(record)
      end

      # Save summary record for the entire run
      save_summary_record(
        start_time,
        attempt,
        duration,
        successful,
        interrupted,
        failed
      )

      cleanup_old_records
    end

    # Report on the results
    # @param authorities [Array<Symbol>] List of authorities attempted to scrape
    # @param exceptions [Hash{Symbol => Exception}] Any exceptions that occurred during scraping
    # `DataQualityMonitor.stats` is checked for :saved and :unprocessed entries
    # @return [void]
    def self.report_on_results(authorities, exceptions)
      if ENV["MORPH_EXPECT_BAD"]
        expect_bad = ENV["MORPH_EXPECT_BAD"].split(",").map(&:strip).map(&:to_sym)
      end
      expect_bad ||= []

      $stderr.flush
      puts "MORPH_EXPECT_BAD=#{ENV.fetch('MORPH_EXPECT_BAD', nil)}" if expect_bad.any?

      # Print summary table
      puts "\nScraping Summary:"
      summary_format = "%-20s %6s %6s %s"

      puts format(summary_format, 'Authority', 'OK', 'Bad', 'Exception')
      puts format(summary_format, "-" * 20, "-" * 6, "-" * 6, "-" * 50)

      authorities.each do |authority|
        stats = ScraperUtils::DataQualityMonitor.stats&.fetch(authority, {}) || {}

        ok_records = stats[:saved] || 0
        bad_records = stats[:unprocessed] || 0

        expect_bad_prefix = expect_bad.include?(authority) ? "[EXPECT BAD] " : ""
        exception_msg = if exceptions[authority]
                          "#{exceptions[authority].class} - #{exceptions[authority].message}"
                        else
                          "-"
                        end
        puts format(summary_format, authority.to_s, ok_records, bad_records,
                    "#{expect_bad_prefix}#{exception_msg}".slice(0, 70))
      end
      puts

      errors = []

      # Check for authorities that were expected to be bad but are now working
      unexpected_working = expect_bad.select do |authority|
        stats = ScraperUtils::DataQualityMonitor.stats&.fetch(authority, {}) || {}
        stats[:saved]&.positive? && !exceptions[authority]
      end

      if unexpected_working.any?
        errors <<
          "WARNING: Remove #{unexpected_working.join(',')} from MORPH_EXPECT_BAD as it now works!"
      end

      # Check for authorities with unexpected errors
      unexpected_errors = authorities
                          .select { |authority| exceptions[authority] }
                          .reject { |authority| expect_bad.include?(authority) }

      if unexpected_errors.any?
        errors << "ERROR: Unexpected errors in: #{unexpected_errors.join(',')} " \
                  "(Add to MORPH_EXPECT_BAD?)"
        unexpected_errors.each do |authority|
          error = exceptions[authority]
          errors << "  #{authority}: #{error.class} - #{error.message}"
        end
      end

      $stdout.flush
      if errors.any?
        errors << "See earlier output for details"
        raise errors.join("\n")
      end

      puts "Exiting with OK status!"
    end

    def self.save_log_record(record)
      ScraperWiki.save_sqlite(
        %w[authority_label run_at],
        record,
        LOG_TABLE
      )
    end

    def self.save_summary_record(start_time, attempt, duration,
                                 successful, interrupted, failed)
      summary = {
        "run_at" => start_time.iso8601,
        "attempt" => attempt,
        "duration" => duration,
        "successful" => successful.join(","),
        "failed" => failed.join(","),
        "interrupted" => interrupted.join(","),
        "successful_count" => successful.size,
        "interrupted_count" => interrupted.size,
        "failed_count" => failed.size,
        "public_ip" => ScraperUtils::MechanizeUtils.public_ip
      }

      ScraperWiki.save_sqlite(
        ["run_at"],
        summary,
        SUMMARY_TABLE
      )
    end

    def self.cleanup_old_records(force: false)
      cutoff = (Date.today - LOG_RETENTION_DAYS).to_s
      return if !force && @last_cutoff == cutoff

      @last_cutoff = cutoff

      [SUMMARY_TABLE, LOG_TABLE].each do |table|
        ScraperWiki.sqliteexecute(
          "DELETE FROM #{table} WHERE date(run_at) < date(?)",
          [cutoff]
        )
      end
    end

    # Extracts meaningful backtrace - 3 lines from ruby/gem and max 6 in total
    def self.extract_meaningful_backtrace(error)
      return nil unless error.respond_to?(:backtrace) && error&.backtrace

      lines = []
      error.backtrace.each do |line|
        lines << line if lines.length < 2 || !line.include?("/vendor/")
        break if lines.length >= 6
      end

      lines.empty? ? nil : lines.join("\n")
    end
  end
end
