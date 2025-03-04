# Reducing Server Load

This document explains various techniques for reducing load on the servers you're scraping.

## Intelligent Date Range Selection

To further reduce server load and speed up scrapers, we provide an intelligent date range selection mechanism
that can reduce server requests by 60% without significantly impacting delay in picking up changes.

The `ScraperUtils::DateRangeUtils#calculate_date_ranges` method provides a smart approach to searching historical
records:

- Always checks the most recent 4 days daily (configurable)
- Progressively reduces search frequency for older records
- Uses a Fibonacci-like progression to create natural, efficient search intervals
- Configurable `max_period` (default is 3 days)
- Merges adjacent search ranges and handles the changeover in search frequency by extending some searches

Example usage in your scraper:

```ruby
date_ranges = ScraperUtils::DateRangeUtils.new.calculate_date_ranges
date_ranges.each do |from_date, to_date, _debugging_comment|
  # Adjust your normal search code to use for this date range
  your_search_records(from_date: from_date, to_date: to_date) do |record|
    # process as normal
  end
end
```

Typical server load reductions:

* Max period 2 days : ~42% of the 33 days selected
* Max period 3 days : ~37% of the 33 days selected (default)
* Max period 5 days : ~35% (or ~31% when days = 45)

See the [DateRangeUtils class documentation](https://rubydoc.info/gems/scraper_utils/ScraperUtils/DateRangeUtils) for customizing defaults and passing options.

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
