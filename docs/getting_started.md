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

Update your `scraper.rb` as per [example scraper](example_scraper.rb)

For more advanced implementations, see the [Interleaving Requests documentation](interleaving_requests.md).

## Logging Tables

The following logging tables are created for use in monitoring failure patterns and debugging issues.
Records are automaticaly cleared after 30 days.

The `ScraperUtils::LogUtils.log_scraping_run` call also logs the information to the `scrape_log` table.

The `ScraperUtils::LogUtils.save_summary_record` call also logs the information to the `scrape_summary` table.

## Next Steps

- [Reducing Server Load](reducing_server_load.md)
- [Mechanize Utilities](mechanize_utilities.md)
- [Debugging](debugging.md)
