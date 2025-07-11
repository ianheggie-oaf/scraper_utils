#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH << "./lib"

require "scraper_utils"
require "parallel"
require "your_scraper"

# Main Scraper class
class Scraper
  AUTHORITIES = YourScraper::AUTHORITIES

  # Process a single authority and returns an array of:
  # * authority_label,
  # * array of records to save,
  # * an array of arrays of unprocessable_records and their exception
  # * nil or a fatal exception,
  def self.scrape_authority(authority_label, attempt)
    puts "\nCollecting feed data for #{authority_label}, attempt: #{attempt}..."

    # Enable in-memory collection mode, which disables saving to file and avoids conflicts
    ScraperUtils::DbUtils.collect_saves!
    unprocessable_record_details = []
    fatal_exception = nil

    begin
      ScraperUtils::DataQualityMonitor.start_authority(authority_label)
      YourScraper.scrape(authority_label) do |record|
        begin
          record["authority_label"] = authority_label.to_s
          ScraperUtils::DbUtils.save_record(record)
        rescue ScraperUtils::UnprocessableRecord => e
          # Log bad record but continue processing unless too many have occurred
          ScraperUtils::DataQualityMonitor.log_unprocessable_record(e, record)
          unprocessable_record_details << [e, record]
        end
      end
    rescue StandardError => e
      warn "#{authority_label}: ERROR: #{e}"
      warn e.backtrace
      fatal_exception = e
    end
    [authority_label, ScraperUtils::DbUtils.collected_saves, unprocessable_record_details, fatal_exception]
  end

  # Process authorities in parallel
  def self.scrape_parallel(authorities, attempt, process_count: 4)
    exceptions = {}
    # Saves immediately in main process
    ScraperUtils::DbUtils.save_immediately!
    Parallel.map(authorities, in_processes: process_count) do |authority_label|
      # Runs in sub process
      scrape_authority(authority_label, attempt)
    end.each do |authority_label, saves, unprocessable, fatal_exception|
      # Runs in main process
      status = fatal_exception ? 'FAILED' : 'OK'
      puts "Saving results of #{authority_label}: #{saves.size} records, #{unprocessable.size} unprocessable #{status}"

      saves.each do |record|
        ScraperUtils::DbUtils.save_record(record)
      end
      unprocessable.each do |e, record|
        ScraperUtils::DataQualityMonitor.log_unprocessable_record(e, record)
        exceptions[authority_label] = e
      end

      if fatal_exception
        puts "  Warning: #{authority_label} failed with: #{fatal_exception.message}"
        puts "  Saved #{saves.size} records before failure"
        exceptions[authority_label] = fatal_exception
      end
    end

    exceptions
  end

  def self.selected_authorities
    ScraperUtils::AuthorityUtils.selected_authorities(AUTHORITIES.keys)
  end

  def self.run(authorities, process_count: 8)
    puts "Scraping authorities in parallel: #{authorities.join(', ')}"
    puts "Using #{process_count} processes"

    start_time = Time.now
    exceptions = scrape_parallel(authorities, 1, process_count: process_count)

    ScraperUtils::LogUtils.log_scraping_run(
      start_time,
      1,
      authorities,
      exceptions
    )

    unless exceptions.empty?
      puts "\n***************************************************"
      puts "Now retrying authorities which earlier had failures"
      puts exceptions.keys.join(", ").to_s
      puts "***************************************************"

      start_time = Time.now
      exceptions = scrape_parallel(exceptions.keys, 2, process_count: process_count)

      ScraperUtils::LogUtils.log_scraping_run(
        start_time,
        2,
        authorities,
        exceptions
      )
    end

    # Report on results, raising errors for unexpected conditions
    ScraperUtils::LogUtils.report_on_results(authorities, exceptions)
  end
end

if __FILE__ == $PROGRAM_NAME
  ENV["MORPH_EXPECT_BAD"] ||= "some,councils"

  process_count = (ENV['MORPH_PROCESSES'] || Etc.nprocessors * 2).to_i

  Scraper.run(Scraper.selected_authorities, process_count: process_count)
end
