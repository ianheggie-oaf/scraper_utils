# Getting Started with ScraperUtils

This guide will help you get started with ScraperUtils for your PlanningAlerts scraper.

## Installation

Add these lines to your [scraper's](https://www.planningalerts.org.au/how_to_write_a_scraper) Gemfile:

```ruby
# Below:
gem "scraperwiki", git: "https://github.com/openaustralia/scraperwiki-ruby.git", branch: "morph_defaults"

# Add:
gem 'scraper_utils'
```

And then execute:

```bash
bundle install
```

## Environment Variables

### `MORPH_AUSTRALIAN_PROXY`

On morph.io set the environment variable `MORPH_AUSTRALIAN_PROXY` to
`http://morph:password@au.proxy.oaf.org.au:8888`
replacing password with the real password.
Alternatively enter your own AUSTRALIAN proxy details when testing.

### `MORPH_EXPECT_BAD`

To avoid morph complaining about sites that are known to be bad,
but you want them to keep being tested, list them on `MORPH_EXPECT_BAD`, for example:

### `MORPH_AUTHORITIES`

Optionally filter authorities for multi authority scrapers
via environment variable in morph > scraper > settings or
in your dev environment:

```bash
export MORPH_AUTHORITIES=noosa,wagga
```

### `DEBUG`

Optionally enable verbose debugging messages when developing:

```bash
export DEBUG=1 # for basic, or 2 for verbose or 3 for tracing nearly everything
```

## Example Scraper Implementation

Update your `scraper.rb` as follows:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH << "./lib"

require "scraper_utils"
require "your_scraper"

# Main Scraper class
class Scraper
  AUTHORITIES = YourScraper::AUTHORITIES

  def scrape(authorities, attempt)
    exceptions = {}
    authorities.each do |authority_label|
      puts "\nCollecting feed data for #{authority_label}, attempt: #{attempt}..."

      begin
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
      rescue StandardError => e
        warn "#{authority_label}: ERROR: #{e}"
        warn e.backtrace
        exceptions[authority_label] = e
      end
    end

    exceptions
  end

  def self.selected_authorities
    ScraperUtils::AuthorityUtils.selected_authorities(AUTHORITIES.keys)
  end

  def self.run(authorities)
    puts "Scraping authorities: #{authorities.join(', ')}"
    start_time = Time.now
    exceptions = new.scrape(authorities, 1)
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
      exceptions = new.scrape(exceptions.keys, 2)
      ScraperUtils::LogUtils.log_scraping_run(
        start_time,
        2,
        authorities,
        exceptions
      )
    end

    ScraperUtils::LogUtils.report_on_results(authorities, exceptions)
  end
end

if __FILE__ == $PROGRAM_NAME
  ENV["MORPH_EXPECT_BAD"] ||= "wagga"
  Scraper.run(Scraper.selected_authorities)
end
```

For more advanced implementations, see the [Interleaving Requests documentation](interleaving_requests.md).

## Next Steps

- [Reducing Server Load](reducing_server_load.md)
- [Mechanize Utilities](mechanize_utilities.md)
- [Debugging](debugging.md)
