ScraperUtils (Ruby)
===================

Utilities to help make planningalerts scrapers, especially multis, easier to develop, run and debug.

## Installation & Configuration

Add to [your scraper's](https://www.planningalerts.org.au/how_to_write_a_scraper) Gemfile:

```ruby
gem "scraperwiki", git: "https://github.com/openaustralia/scraperwiki-ruby.git", branch: "morph_defaults"
gem 'scraper_utils'
```

For detailed setup and configuration options,
see {file:docs/getting_started.md Getting Started guide}

## Key Features

### Well-Behaved Web Client

- Configure Mechanize agents with sensible defaults
- Supports extra actions required to get to results page
- {file:docs/mechanize_utilities.md Learn more about Mechanize utilities}

### Error Handling & Quality Monitoring

- Record-level error handling with appropriate thresholds
- Data quality monitoring during scraping
- Detailed logging and reporting

### Developer Tools

- Enhanced debugging utilities
- Simple logging with authority context
- {file:docs/debugging.md Learn more about debugging}

### Spec Validation

- Validate geocodable addresses and reasonable descriptions
- Check info URL availability and content
- Support for bot protection detection
- {file:docs/enhancing_specs.md Learn more about spec validation}

## API Documentation

Complete API documentation is available at [scraper_utils | RubyDoc.info](https://rubydoc.info/gems/scraper_utils).

## Ruby Versions

This gem is designed to be compatible with Ruby versions supported by morph.io:

* Ruby 3.2.2 - requires the `platform` file to contain `heroku_18` in the scraper
* Ruby 2.5.8 - `heroku_16` (the default)

## Development

After checking out the repo, run `bin/setup` to install dependencies.
Then, run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests with working tests are welcome
on [ianheggie-oaf/scraper_utils | GitHub](https://github.com/ianheggie-oaf/scraper_utils).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
