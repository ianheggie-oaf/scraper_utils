ScraperUtils (Ruby)
===================

Utilities to help make planningalerts scrapers, especially multis easier to develop, run and debug.

WARNING: This is still under development! Breaking changes may occur in version 0!

## Installation

Add these line to your application's Gemfile:

```ruby
gem "scraperwiki", git: "https://github.com/openaustralia/scraperwiki-ruby.git", branch: "morph_defaults"
gem 'scraper_utils'
```

And then execute:

    $ bundle

Or install it yourself for testing:

    $ gem install scraper_utils

## Usage

### Environment variables

Optionally filter authorities via environment variable in morph > scraper > settings or 
in your dev environment:

```bash
export MORPH_AUTHORITIES=noosa,wagga
```

### Example updated `scraper.rb` file

Update your `scraper.rb` as per the following example:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH << "./lib"

require "scraper_utils"
require "technology_one_scraper"

# Main Scraper class
class Scraper
  AUTHORITIES = TechnologyOneScraper::AUTHORITIES

  def self.scrape(authorities, attempt)
    results = {}
    authorities.each do |authority_label|
      these_results = results[authority_label] = {}
      begin
        records_scraped = 0
        unprocessable_records = 0
        # Allow 5 + 10% unprocessable records
        too_many_unprocessable = -5.0
        use_proxy = AUTHORITIES[authority_label][:australian_proxy] && ScraperUtils.australian_proxy
        next if attempt > 2 && !use_proxy

        puts "",
             "Collecting feed data for #{authority_label}, attempt: #{attempt}" \
               "#{use_proxy ? ' (via proxy)' : ''} ..."
        # Change scrape to accept a use_proxy flag and return an unprocessable flag
        # it should rescue ScraperUtils::UnprocessableRecord thrown deeper in the scraping code and
        # set unprocessable
        TechnologyOneScraper.scrape(use_proxy, authority_label) do |record, unprocessable|
          unless unprocessable
            begin
              record["authority_label"] = authority_label.to_s
              ScraperUtils::DbUtils.save_record(record)
            rescue ScraperUtils::UnprocessableRecord => e
              # validation error
              unprocessable = true
              these_results[:error] = e
            end
          end
          if unprocessable
            unprocessable_records += 1
            these_results[:unprocessable_records] = unprocessable_records
            too_many_unprocessable += 1
            raise "Too many unprocessable records" if too_many_unprocessable.positive?
          else
            records_scraped += 1
            these_results[:records_scraped] = records_scraped
            too_many_unprocessable -= 0.1
          end
        end
      rescue StandardError => e
        warn "#{authority_label}: ERROR: #{e}"
        warn e.backtrace || "No backtrace available"
        these_results[:error] = e
      end
    end
    results
  end

  def self.selected_authorities
    ScraperUtils::AuthorityUtils.selected_authorities(AUTHORITIES.keys)
  end

  def self.run(authorities)
    puts "Scraping authorities: #{authorities.join(', ')}"
    start_time = Time.now
    results = scrape(authorities, 1)
    ScraperUtils::LogUtils.log_scraping_run(
      start_time,
      1,
      authorities,
      results
    )

    retry_errors = results.select do |_auth, result|
      result[:error] && !result[:error].is_a?(ScraperUtils::UnprocessableRecord)
    end.keys

    unless retry_errors.empty?
      puts "",
           "***************************************************"
      puts "Now retrying authorities which earlier had failures"
      puts retry_errors.join(", ").to_s
      puts "***************************************************"

      start_retry = Time.now
      retry_results = scrape(retry_errors, 2)
      ScraperUtils::LogUtils.log_scraping_run(
        start_retry,
        2,
        retry_errors,
        retry_results
      )

      retry_results.each do |auth, result|
        unless result[:error] && !result[:error].is_a?(ScraperUtils::UnprocessableRecord)
          results[auth] = result
        end
      end.keys
      retry_no_proxy = retry_results.select do |_auth, result|
        result[:used_proxy] && result[:error] &&
          !result[:error].is_a?(ScraperUtils::UnprocessableRecord)
      end.keys

      unless retry_no_proxy.empty?
        puts "",
             "*****************************************************************"
        puts "Now retrying authorities which earlier had failures without proxy"
        puts retry_no_proxy.join(", ").to_s
        puts "*****************************************************************"

        start_retry = Time.now
        second_retry_results = scrape(retry_no_proxy, 3)
        ScraperUtils::LogUtils.log_scraping_run(
          start_retry,
          3,
          retry_no_proxy,
          second_retry_results
        )
        second_retry_results.each do |auth, result|
          unless result[:error] && !result[:error].is_a?(ScraperUtils::UnprocessableRecord)
            results[auth] = result
          end
        end.keys
      end
    end

    # Report on results, raising errors for unexpected conditions
    ScraperUtils::LogUtils.report_on_results(authorities, results)
  end
end

if __FILE__ == $PROGRAM_NAME
  # Default to list of authorities we can't or won't fix in code, explain why
  # wagga: url redirects and reports Application error, main site says to use NSW Planning Portal from 1 July 2021
  #        which doesn't list any DA's for wagga wagga!

  ENV["MORPH_EXPECT_BAD"] ||= "wagga"
  Scraper.run(Scraper.selected_authorities)
end
```

Then deeper in your code update:

* Change scrape to accept a `use_proxy` flag and return an `unprocessable` flag
* it should rescue ScraperUtils::UnprocessableRecord thrown deeper in the scraping code and
  set and yield unprocessable eg: `TechnologyOneScraper.scrape(use_proxy, authority_label) do |record, unprocessable|`

```ruby
require "scraper_utils"
#...
module TechnologyOneScraper
  # Note the extra parameter: use_proxy
  def self.scrape(use_proxy, authority)
    raise "Unexpected authority: #{authority}" unless AUTHORITIES.key?(authority)

    scrape_period(use_proxy, AUTHORITIES[authority]) do |record, unprocessable|
      yield record, unprocessable
    end
  end
  
  # ... rest of code ...

  # Note the extra parameters: use_proxy and timeout
  def self.scrape_period(use_proxy,
    url:, period:, webguest: "P1.WEBGUEST", disable_ssl_certificate_check: false,
    australian_proxy: false, timeout: nil
  )
    agent = ScraperUtils::MechanizeUtils.mechanize_agent(use_proxy: use_proxy, timeout: timeout)
    agent.verify_mode = OpenSSL::SSL::VERIFY_NONE if disable_ssl_certificate_check
    
    # ... rest of code ...

    # Update yield to return unprocessable as well as record

  end
  # ... rest of code ...
end
```

### Debugging Techniques

The following code will print dbugging info if you set:

```bash
export DEBUG=1
```

Add the following immediately before requesting or examining pages

```ruby
require 'scraper_utils'

# Debug an HTTP request
ScraperUtils::DebugUtils.debug_request(
  "GET", 
  "https://example.com/planning-apps", 
  parameters: { year: 2023 },
  headers: { "Accept" => "application/json" }
)

# Debug a web page
ScraperUtils::DebugUtils.debug_page(page, "Checking search results page")

# Debug a specific page selector
ScraperUtils::DebugUtils.debug_selector(page, '.results-table', "Looking for development applications")
```

## Development

After checking out the repo, run `bin/setup` to install dependencies.
Then, run `rake test` to run the tests.

You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

To release a new version, update the version number in `version.rb`, and
then run `bundle exec rake release`,
which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ianheggie-oaf/scraper_utils

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

