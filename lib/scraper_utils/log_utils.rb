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
    # @param results [Hash] Results for each authority containing:
    #   - :records_scraped [Integer] Number of records successfully scraped
    #   - :unprocessable_records [Integer] Optional Number of unprocessable record like regions
    #   - :error [Exception, nil] Any exception that occurred during scraping
    #   - :proxy_used [Boolean] Whether a proxy was used
    # @return [void]
    def self.log_scraping_run(start_time, attempt, authorities, results)
      raise ArgumentError, "Invalid start time" unless start_time.is_a?(Time)
      raise ArgumentError, "Authorities must be a non-empty array" if authorities.empty?

      end_time = Time.now
      duration = (end_time - start_time).round(1)

      successful = []
      failed = []
      interrupted = []

      authorities.each do |authority_label|
        result = results[authority_label] || {}

        status = if result[:records_scraped]&.positive?
                   result[:error] ? :interrupted : :successful
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
          "records_scraped" => result[:records_scraped] || 0,
          "unprocessable_records" => result[:unprocessable_records] || 0,
          "used_proxy" => result[:proxy_used] ? 1 : 0,
          "status" => status.to_s,
          "error_message" => result[:error]&.message,
          "error_class" => result[:error]&.class&.to_s,
          "error_backtrace" => extract_meaningful_backtrace(result[:error])
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

    def self.report_on_results(authorities, results)
      expect_bad = ENV["MORPH_EXPECT_BAD"]&.split(",")&.map(&:to_sym) || []

      puts "MORPH_EXPECT_BAD=#{ENV['MORPH_EXPECT_BAD']}" if expect_bad.any?

      errors = []

      # Check for authorities that were expected to be bad but are now working
      unexpected_working = expect_bad.select do |authority|
        result = results[authority]
        result && result[:records_scraped]&.positive? && result[:error].nil?
      end

      if unexpected_working.any?
        errors << "WARNING: Remove #{unexpected_working.join(',')} from EXPECT_BAD as it now works!"
      end

      # Check for authorities with unexpected errors
      unexpected_errors = authorities
                          .select { |authority| results[authority]&.dig(:error) }
                          .reject { |authority| expect_bad.include?(authority) }

      if unexpected_errors.any?
        errors << "ERROR: Unexpected errors in: #{unexpected_errors.join(',')} " \
          "(Add to MORPH_EXPECT_BAD?)"
        unexpected_errors.each do |authority|
          error = results[authority][:error]
          errors << "  #{authority}: #{error.class} - #{error.message}"
        end
      end

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
        "failed_count" => failed.size
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
