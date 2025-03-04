ScraperUtils (Ruby)
===================

Utilities to help make planningalerts scrapers, especially multis, easier to develop, run and debug.

For Server Administrators
-------------------------

The ScraperUtils library is designed to be a respectful citizen of the web. If you're a server administrator and notice
our scraper accessing your systems, here's what you should know:

### How to Control Our Behavior

Our scraper utilities respect the standard server **robots.txt** control mechanisms (by default).
To control our access:

- Add a section for our user agent: `User-agent: ScraperUtils` (default)
- Set a crawl delay, eg: `Crawl-delay: 20`
- If needed specify disallowed paths: `Disallow: /private/`

### We play nice with your servers

Our goal is to access public planning information with minimal impact on your services. The following features are on by
default:

- **Identify themselves**: Our user agent clearly indicates who we are and provides a link to the project repository:
  `Mozilla/5.0 (compatible; ScraperUtils/0.2.0 2025-02-22; +https://github.com/ianheggie-oaf/scraper_utils)`

- **Limit server load**:
    - We wait double your response time before making another request to avoid being a significant load on your server
    - We also randomly add extra delays to give your server a chance to catch up with background tasks

We also provide scraper developers other features to reduce overall load as well.

For Scraper Developers
----------------------

We provide utilities to make developing, running and debugging your scraper easier in addition to the base utilities
mentioned above.

## Installation & Configuration

Add to your [scraper's](https://www.planningalerts.org.au/how_to_write_a_scraper) Gemfile:

```ruby
gem "scraperwiki", git: "https://github.com/openaustralia/scraperwiki-ruby.git", branch: "morph_defaults"
gem 'scraper_utils'
```

For detailed setup and configuration options, see the [Getting Started guide](docs/getting_started.md).

## Key Features

### Well-Behaved Web Client

- Configure Mechanize agents with sensible defaults
- Automatic rate limiting based on server response times
- Supports robots.txt and crawl-delay directives
- [Learn more about Mechanize utilities](docs/mechanize_utilities.md)

### Optimize Server Load

- Intelligent date range selection (reduce server load by up to 60%)
- Cycle utilities for rotating search parameters
- [Learn more about reducing server load](docs/reducing_server_load.md)

### Improve Scraper Efficiency

- Interleave requests to optimize run time
- [Learn more about interleaving requests](docs/interleaving_requests.md)
- Randomize processing order for more natural request patterns
- [Learn more about randomizing requests](docs/randomizing_requests.md)

### Error Handling & Quality Monitoring

- Record-level error handling with appropriate thresholds
- Data quality monitoring during scraping
- Detailed logging and reporting

### Developer Tools

- Enhanced debugging utilities
- Simple logging with authority context
- [Learn more about debugging](docs/debugging.md)

## API Documentation

Complete API documentation is available at [RubyDoc.info](https://rubydoc.info/gems/scraper_utils).

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
on [GitHub](https://github.com/ianheggie-oaf/scraper_utils).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
