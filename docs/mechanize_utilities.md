# Mechanize Utilities

This document provides detailed information about the Mechanize utilities provided by ScraperUtils.

## MechanizeUtils

The `ScraperUtils::MechanizeUtils` module provides utilities for configuring and using Mechanize for web scraping.

### Creating a Mechanize Agent

```ruby
agent = ScraperUtils::MechanizeUtils.mechanize_agent(**options)
```

### Configuration Options

Add `client_options` to your AUTHORITIES configuration and move any of the following settings into it:

* `timeout: Integer` - Timeout for agent connections in case the server is slower than normal
* `australian_proxy: true` - Use the proxy url in the `MORPH_AUSTRALIAN_PROXY` env variable if the site is geo-locked
* `disable_ssl_certificate_check: true` - Disabled SSL verification for old / incorrect certificates

Then adjust your code to accept `client_options` and pass then through to:
`ScraperUtils::MechanizeUtils.mechanize_agent(client_options || {})`
to receive a `Mechanize::Agent` configured accordingly.

The agent returned is configured using Mechanize hooks to implement the desired delays automatically.

### Default Configuration

By default, the Mechanize agent is configured with the following settings.
As you can see, the defaults can be changed using env variables or via code.

Note - compliant mode forces max_load to be set to a value no greater than 50.

```ruby
ScraperUtils::MechanizeUtils::AgentConfig.configure do |config|
  config.default_timeout = ENV.fetch('MORPH_TIMEOUT', DEFAULT_TIMEOUT).to_i # 60
  config.default_disable_ssl_certificate_check = !ENV.fetch('MORPH_DISABLE_SSL_CHECK', nil).to_s.empty? # false
  config.default_australian_proxy = !ENV.fetch('MORPH_USE_PROXY', nil).to_s.empty? # false
  config.default_user_agent = ENV.fetch('MORPH_USER_AGENT', nil) # Uses Mechanize user agent
end
```

For full details, see the [MechanizeUtils class documentation](https://rubydoc.info/gems/scraper_utils/ScraperUtils/MechanizeUtils).

## MechanizeActions

The `ScraperUtils::MechanizeActions` class provides a convenient way to execute a series of actions (like clicking links, filling forms) on a Mechanize page.

### Action Format

```ruby
actions = [
  [:click, "Find an application"],
  [:click, ["Submitted Last 28 Days", "Submitted Last 7 Days"]],
  [:block, ->(page, args, agent, results) { [new_page, result_data] }]
]

processor = ScraperUtils::MechanizeActions.new(agent)
result_page = processor.process(page, actions)
```

### Supported Actions

- `:click` - Clicks on a link or element matching the provided selector
- `:block` - Executes a custom block of code for complex scenarios

### Selector Types

- Text selector (default): `"Find an application"`
- CSS selector: `"css:.button"`
- XPath selector: `"xpath://a[@class='button']"`

### Replacements

You can use replacements in your action parameters:

```ruby
replacements = { FROM_DATE: "2022-01-01", TO_DATE: "2022-03-01" }
processor = ScraperUtils::MechanizeActions.new(agent, replacements)

# Use replacements in actions
actions = [
  [:click, "Search between {FROM_DATE} and {TO_DATE}"]
]
```

For full details, see the [MechanizeActions class documentation](https://rubydoc.info/gems/scraper_utils/ScraperUtils/MechanizeActions).
