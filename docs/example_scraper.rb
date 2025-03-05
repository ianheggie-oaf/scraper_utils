#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH << "./lib"

require "scraper_utils"
require "your_scraper"

# Main Scraper class
class Scraper
  AUTHORITIES = YourScraper::AUTHORITIES

  # ADD: attempt argument
  def scrape(authorities, attempt)
    exceptions = {}
    # ADD: Report attempt number
    authorities.each do |authority_label|
      puts "\nCollecting feed data for #{authority_label}, attempt: #{attempt}..."

      # REPLACE section with:
      ScraperUtils::DataQualityMonitor.start_authority(authority_label)
      YourScraper.scrape(authority_label) do |record|
        begin
          record["authority_label"] = authority_label.to_s
          ScraperUtils::DbUtils.save_record(record)
        rescue ScraperUtils::UnprocessableRecord => e
          ScraperUtils::DataQualityMonitor.log_unprocessable_record(e, record)
          exceptions[authority_label] = e
        end
      end
      # END OF REPLACE
    rescue StandardError => e
      warn "#{authority_label}: ERROR: #{e}"
      warn e.backtrace
      exceptions[authority_label] = e
    end

    exceptions
  end

  def self.selected_authorities
    ScraperUtils::AuthorityUtils.selected_authorities(AUTHORITIES.keys)
  end

  def self.run(authorities)
    puts "Scraping authorities: #{authorities.join(', ')}"
    start_time = Time.now
    exceptions = scrape(authorities, 1)
    # Set start_time and attempt to the call above and log run below
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
      exceptions = scrape(exceptions.keys, 2)
      # Set start_time and attempt to the call above and log run below
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
  # Default to list of authorities we can't or won't fix in code, explain why
  # some: url-for-issue Summary Reason
  # councils : url-for-issue Summary Reason

  ENV["MORPH_EXPECT_BAD"] ||= "some,councils"
  Scraper.run(Scraper.selected_authorities)
end
