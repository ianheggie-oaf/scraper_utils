# Testing Custom Scrapers

Custom scrapers often lack proper specs but still need quality validation. This gem provides a simple executable to
validate your scraped data.

## Setup

Add to your `Gemfile`:

```ruby
gem "scraper_utils", "~> 0.8.2"
gem "rake", "~> 13.0"
```

Copy the example files to your scraper directory:

- `docs/example_custom_Rakefile` → `Rakefile`
- `docs/example_dot_scraper_validation.yml` → `.scraper_validation.yml`

## Usage

### Command Line

Once you have run the scraper (`bundle exec ruby scraper.rb`) you can manually run the command:

```bash
# Run with defaults
validate_scraper_data

# Custom thresholds
validate_scraper_data --geocodable-percentage 80 --description-percentage 60

# For scrapers with bot protection
validate_scraper_data --bot-check-expected
```

### Rake Tasks

```bash
bundle exec rake           # Run scraper then validate (default)
bundle exec rake test      # Same as above
bundle exec rake scrape    # Just run scraper
bundle exec rake validate  # Just validate existing data
bundle exec rake clean     # Remove data.sqlite
```

## Configuration

Edit `.scraper_validation.yml` to set validation thresholds:

```yaml
geocodable_percentage: 70    # Min % of geocodable addresses
description_percentage: 55   # Min % of reasonable descriptions
info_url_percentage: 75      # Min % of info URL detail checks
bot_check_expected: false    # Set true when detail pages have reCAPTCHA/Cloudflare bot checks
```

## What Gets Validated

- **Addresses**: Checks for proper Australian address format (street type, state, postcode)
- **Descriptions**: Ensures descriptions aren't placeholders and have 3+ words
- **Info URLs**: Validates URLs return status 200 and the page contains expected details
- **Global URLs**: Auto-detects if all records use the same info URL and validates it's accessible

## Integration with CI

Add to your CI pipeline:

```bash
bundle install
rake test
```

The validation will fail with clear error messages if data quality is insufficient, helping catch scraping issues early.
