# Reducing Server Load

This document explains various techniques for reducing load on the servers you're scraping.


## Cycle Utilities

Simple utility for cycling through options based on Julian day number to reduce server load and make your scraper seem less bot-like.

If the site uses tags like 'L28', 'L14' and 'L7' for the last 28, 14 and 7 days, an alternative solution
is to cycle through ['L28', 'L7', 'L14', 'L7'] which would drop the load by 50% and be less bot-like.

```ruby
# Toggle between main and alternate behaviour
alternate = ScraperUtils::CycleUtils.position(2).even?

# OR cycle through a list of values day by day:
period = ScraperUtils::CycleUtils.pick(['L28', 'L7', 'L14', 'L7'])

# Use with any cycle size
pos = ScraperUtils::CycleUtils.position(7) # 0-6 cycle

# Test with specific date
pos = ScraperUtils::CycleUtils.position(3, date: Date.new(2024, 1, 5))

# Override for testing
# CYCLE_POSITION=2 bundle exec ruby scraper.rb
```

For full details, see the [CycleUtils class documentation](https://rubydoc.info/gems/scraper_utils/ScraperUtils/CycleUtils).
