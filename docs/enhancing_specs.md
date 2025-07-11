# Enhancing specs

ScraperUtils provides validation methods to help with checking scraping results:

* `ScraperUtils::SpecSupport.geocodable?` - Check if an address is likely to be geocodable
* `ScraperUtils::SpecSupport.reasonable_description?` - Check if a description looks reasonable
* `ScraperUtils::SpecSupport.validate_addresses_are_geocodable!` - Validate percentage of geocodable addresses
* `ScraperUtils::SpecSupport.validate_descriptions_are_reasonable!` - Validate percentage of reasonable descriptions
* `ScraperUtils::SpecSupport.validate_uses_one_valid_info_url!` - Validate single global info_url usage and availability
* `ScraperUtils::SpecSupport.validate_info_urls_have_expected_details!` - Validate info_urls contain expected content

## Example Code:

```ruby
# frozen_string_literal: true

require "timecop"
require_relative "../scraper"

RSpec.describe Scraper do
  # Authorities that use bot protection (reCAPTCHA, Cloudflare, etc.) on detail pages (info_url)
  AUTHORITIES_WITH_BOT_PROTECTION = %i[
    some_authority
    another_authority
  ].freeze

  describe ".scrape" do
def fetch_url_with_redirects(url)
      agent = Mechanize.new
      page = agent.get(url)
      if YourScraper::Pages::TermsAndConditions.on_page?(page)
        puts "Agreeing to terms and conditions for #{url}"
        YourScraper::Pages::TermsAndConditions.click_agree(page)
        page = agent.get(url)
      end
      page
    end

    def test_scrape(authority)
      ScraperWiki.close_sqlite
      FileUtils.rm_f("data.sqlite")

      VCR.use_cassette(authority) do
        date = Date.new(2025, 4, 15)
        Timecop.freeze(date) do
          Scraper.scrape([authority], 1)
        end
      end

      expected = if File.exist?("spec/expected/#{authority}.yml")
                   YAML.safe_load(File.read("spec/expected/#{authority}.yml"))
                 else
                   []
                 end
      results = ScraperWiki.select("* from data order by council_reference")

      ScraperWiki.close_sqlite

      if results != expected
        # Overwrite expected so that we can compare with version control
        # (and maybe commit if it is correct)
        File.open("spec/expected/#{authority}.yml", "w") do |f|
          f.write(results.to_yaml)
        end
      end

      expect(results).to eq expected

      if results.any?
        ScraperUtils::SpecSupport.validate_addresses_are_geocodable!(results, percentage: 70, variation: 3)

        ScraperUtils::SpecSupport.validate_descriptions_are_reasonable!(results, percentage: 55, variation: 3)

        global_info_url = Scraper::AUTHORITIES[authority][:info_url]
        # OR 
        # global_info_url = results.first['info_url'] 
        bot_check_expected = AUTHORITIES_WITH_BOT_PROTECTION.include?(authority)

        unless ENV['DISABLE_INFO_URL_CHECK']
          if global_info_url
            ScraperUtils::SpecSupport.validate_uses_one_valid_info_url!(results, global_info_url, bot_check_expected: bot_check_expected) do |url|
              fetch_url_with_redirects(url)
            end
          else
            ScraperUtils::SpecSupport.validate_info_urls_have_expected_details!(results, percentage: 70, variation: 3, bot_check_expected: bot_check_expected) do |url|
              fetch_url_with_redirects(url)
            end
          end
        end
      end
    end

    Scraper.selected_authorities.each do |authority|
      it authority do
        test_scrape(authority)
      end
    end
  end
end
```

## Individual validation methods:

### Address validation

```ruby
# Check if single address is geocodable
ScraperUtils::SpecSupport.geocodable?('123 Smith Street, Sydney NSW 2000')

# Validate percentage of geocodable addresses
ScraperUtils::SpecSupport.validate_addresses_are_geocodable!(results, percentage: 50, variation: 3)
```

### Description validation

```ruby
# Check if single description is reasonable
ScraperUtils::SpecSupport.reasonable_description?('Construction of new building')

# Validate percentage of reasonable descriptions
ScraperUtils::SpecSupport.validate_descriptions_are_reasonable!(results, percentage: 50, variation: 3)
```

### Info URL validation

```ruby
# For authorities with global info_url
ScraperUtils::SpecSupport.validate_uses_one_valid_info_url!(results, 'https://example.com/search')

# For authorities with bot protection
ScraperUtils::SpecSupport.validate_uses_one_valid_info_url!(results, 'https://example.com/search', bot_check_expected: true)

# For authorities with unique info_urls per record
ScraperUtils::SpecSupport.validate_info_urls_have_expected_details!(results, percentage: 75, variation: 3)

# For authorities with unique info_urls that may have bot protection
ScraperUtils::SpecSupport.validate_info_urls_have_expected_details!(results, percentage: 75, variation: 3, bot_check_expected: true)
```

### Custom URL fetching

For sites requiring special handling (terms agreement, cookies, etc.):

```ruby
# Custom URL fetching with block
ScraperUtils::SpecSupport.validate_uses_one_valid_info_url!(results, url) do |url|
  fetch_url_with_redirects(url)  # Your custom fetch implementation
end

ScraperUtils::SpecSupport.validate_info_urls_have_expected_details!(results) do |url|
  fetch_url_with_redirects(url)  # Handle terms agreement, cookies, etc.
end
```

## Bot Protection Handling

The `bot_check_expected` parameter allows validation methods to accept bot protection as valid responses:

**When bot protection is detected:**

- HTTP status codes: 403 (Forbidden), 429 (Too Many Requests)
- Content indicators: "recaptcha", "cloudflare", "are you human", "bot detection", "security check", "verify you are
  human", "access denied", "blocked", "captcha"

**Usage patterns:**

- Set `bot_check_expected: false` (default) - requires 200 responses, fails on bot protection
- Set `bot_check_expected: true` - accepts bot protection as valid, useful for authorities known to use anti-bot
  measures

All validation methods accept `percentage` (minimum percentage required) and `variation` (additional tolerance)
parameters for consistent configuration.

