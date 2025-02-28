ScraperUtils (Ruby)
===================

Utilities to help make planningalerts scrapers, especially multis, easier to develop, run and debug.

WARNING: This is still under development! Breaking changes may occur in version 0.x!

For Server Administrators
-------------------------

The ScraperUtils library is designed to be a respectful citizen of the web. If you're a server administrator and notice
our scraper accessing your systems, here's what you should know:

### How to Control Our Behavior

Our scraper utilities respect the standard server **robots.txt** control mechanisms (by default). To control our access:

- Add a section for our user agent: `User-agent: ScraperUtils` (default)
- Set a crawl delay: `Crawl-delay: 5`
- If needed specify disallowed paths: `Disallow: /private/`

### Built-in Politeness Features

Even without specific configuration, our scrapers will, by default:

- **Identify themselves**: Our user agent clearly indicates who we are and provides a link to the project repository:
  `Mozilla/5.0 (compatible; ScraperUtils/0.2.0 2025-02-22; +https://github.com/ianheggie-oaf/scraper_utils)`

- **Limit server load**: We introduce delays to avoid undue load on your server's by default based on your response
  time.
  The slower your server is running, the longer the delay we add between requests to help you.
  In the default "compliant mode" this defaults to 20% and custom settings are capped at 33% maximum.

- **Add randomized delays**: We add random delays between requests to avoid creating regular traffic patterns that might
  impact server performance (enabled by default).

Our goal is to access public planning information without negatively impacting your services.

Installation
------------

Add these line to your application's Gemfile:

```ruby
gem "scraperwiki", git: "https://github.com/openaustralia/scraperwiki-ruby.git", branch: "morph_defaults"
gem 'scraper_utils'
```

And then execute:

    $ bundle

Usage
-----

### Ruby Versions

This gem is designed to be compatible the latest ruby supported by morph.io - other versions may work, but not tested:

* ruby 3.2.2 - requires the `platform` file to contain `heroku_18` in the scraper
* ruby 2.5.8 - `heroku_16` (the default)

### Environment variables

#### `MORPH_AUSTRALIAN_PROXY`

On morph.io set the environment variable `MORPH_AUSTRALIAN_PROXY` to
`http://morph:password@au.proxy.oaf.org.au:8888`
replacing password with the real password.
Alternatively enter your own AUSTRALIAN proxy details when testing.

#### `MORPH_EXPECT_BAD`

To avoid morph complaining about sites that are known to be bad,
but you want them to keep being tested, list them on `MORPH_EXPECT_BAD`, for example:

#### `MORPH_AUTHORITIES`

Optionally filter authorities for multi authority scrapers
via environment variable in morph > scraper > settings or
in your dev environment:

```bash
export MORPH_AUTHORITIES=noosa,wagga
```

#### `DEBUG`

Optionally enable verbose debugging messages when developing:

```bash
export DEBUG=1
```

### Extra Mechanize options

Add `client_options` to your AUTHORITIES configuration and move any of the following settings into it:

* `timeout: Integer` - Timeout for agent connections in case the server is slower than normal
* `australian_proxy: true` - Use the proxy url in the `MORPH_AUSTRALIAN_PROXY` env variable if the site is geo-locked
* `disable_ssl_certificate_check: true` - Disabled SSL verification for old / incorrect certificates

See the documentation on `ScraperUtils::MechanizeUtils::AgentConfig` for more options

Then adjust your code to accept `client_options` and pass then through to:
`ScraperUtils::MechanizeUtils.mechanize_agent(client_options || {})`
to receive a `Mechanize::Agent` configured accordingly.

The agent returned is configured using Mechanize hooks to implement the desired delays automatically.

### Default Configuration

By default, the Mechanize agent is configured with the following settings.

```ruby
ScraperUtils::MechanizeUtils::AgentConfig.configure do |config|
  config.default_timeout = 60
  config.default_compliant_mode = true
  config.default_random_delay = 3
  config.default_max_load = 20 # percentage
  config.default_disable_ssl_certificate_check = false
  config.default_australian_proxy = false
end
```

You can modify these global defaults before creating any Mechanize agents. These settings will be used for all Mechanize
agents created by `ScraperUtils::MechanizeUtils.mechanize_agent` unless overridden by passing parameters to that method.

To speed up testing, set the following in `spec_helper.rb`:

```ruby
ScraperUtils::MechanizeUtils::AgentConfig.configure do |config|
  config.default_random_delay = nil
  config.default_max_load = 33
end
```

### Example updated `scraper.rb` file

Update your `scraper.rb` as per the [example scraper](docs/example_scraper.rb).

Your code should raise ScraperUtils::UnprocessableRecord when there is a problem with the data presented on a page for a
record.
Then just before you would normally yield a record for saving, rescue that exception and:

* Call `ScraperUtils::DataQualityMonitor.log_unprocessable_record(e, record)`
* NOT yield the record for saving

In your code update where create a mechanize agent (often `YourScraper.scrape_period`) and the `AUTHORITIES` hash
to move Mechanize agent options (like `australian_proxy` and `timeout`) to a hash under a new key: `client_options`.
For example:

```ruby
require "scraper_utils"
#...
module YourScraper
  # ... some code ...

  # Note the extra parameter: client_options
  def self.scrape_period(url:, period:, webguest: "P1.WEBGUEST",
                         client_options: {}
  )
    agent = ScraperUtils::MechanizeUtils.mechanize_agent(**client_options)

    # ... rest of code ...
  end

  # ... rest of code ...
end
```

### Debugging Techniques

The following code will cause debugging info to be output:

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

Interleaving Requests
---------------------

The `ScraperUtils::FiberScheduler` provides a lightweight utility that:

* works on the other authorities whilst in the delay period for an authorities next request
* thus optimizing the total scraper run time
* allows you to increase the random delay for authorities without undue effect on total run time
* For the curious, it uses [ruby fibers](https://ruby-doc.org/core-2.5.8/Fiber.html) rather than threads as that is
  a simpler system and thus easier to get right, understand and debug!

To enable change the scrape method to be like [example scrape method using fibers](docs/example_scrape_with_fibers.rb) 

And use `ScraperUtils::FiberScheduler.log` instead of `puts` when logging within the authority processing code.
This will prefix the output lines with the authority name, which is needed since the system will interleave the work and
thus the output.

This uses `ScraperUtils::RandomizeUtils` as described below. Remember to add the recommended line to `spec/spec_heper.rb`.

Randomizing Requests
--------------------
 
Pass a `Collection` or `Array` to `ScraperUtils::RandomizeUtils.randomize_order` to randomize it in production, but receive in as is when testing.

Use this with the list of records scraped from an index to randomise the requests to be less Bot like.

### Spec setup

You should enforce sequential mode when testing by adding the following code to `spec/spec_helper.rb`:
```
ScraperUtils::RandomizeUtils.sequential = true
```

Note: 
* You can also force sequential mode by setting the env variable `MORPH_PROCESS_SEQUENTIALLY` to a value, eg: `1`
* testing using VCR requires sequential mode

Development
-----------

After checking out the repo, run `bin/setup` to install dependencies.
Then, run `rake test` to run the tests.

You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

To release a new version, update the version number in `version.rb`, and
then run `bundle exec rake release`,
which will create a git tag for the version, push git commits and tags, and push the `.gem` file
to [rubygems.org](https://rubygems.org).

NOTE: You need to use ruby 3.2.2 instead of 2.5.8 to release to OTP protected accounts.

Contributing
------------

Bug reports and pull requests with working tests are welcome on [GitHub](https://github.com/ianheggie-oaf/scraper_utils)

CHANGELOG.md is maintained by the author aiming to follow https://github.com/vweevers/common-changelog

License
-------

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

