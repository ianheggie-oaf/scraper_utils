# Parallel Scraping with ScraperUtils

This guide shows how to parallelize your multi-authority scraper to significantly reduce run times.

## When to Use Parallel Scraping

Use parallel scraping when:
- You have 10+ authorities taking significant time each
- Authorities are independent (no shared state)
- You want to reduce total scraper run time from hours to minutes

## Installation

Add the parallel gem to your Gemfile:

```ruby
gem "scraperwiki", git: "https://github.com/openaustralia/scraperwiki-ruby.git", branch: "morph_defaults"
gem 'scraper_utils'
gem 'parallel'  # Add this line
```

## Modified Scraper Implementation

See `example_parallel_scraper.rb` as an example of how to convert your existing scraper to use parallel processing.

## Key Changes from Sequential Version

1. **Added `parallel` gem** to Gemfile
2. **Split scraping logic** into `scrape_authority` (single authority) and `scrape_parallel` (coordinator)
3. **Enable collection mode** with `ScraperUtils::DbUtils.collect_saves!` in each subprocess
4. **Return results** as `[authority_label, saves, unprocessable, exception]` from each subprocess
5. **Save in main process** to avoid SQLite locking issues
6. **Preserve error handling**: UnprocessableRecord exceptions logged but don't re-raise

## Configuration Options

### Process Count

Control the number of parallel processes:

```ruby
# In code
process_count = (ENV['MORPH_PROCESSES'] || Etc.nprocessors * 2).to_i
Scraper.run(authorities, process_count: process_count)

# Via environment variable
export MORPH_PROCESSES=6
```

Start with 4 processes and adjust based on:
- Available CPU cores
- Memory usage
- Network bandwidth
- Target site responsiveness

### Environment Variables

All existing environment variables work unchanged:
- `MORPH_AUTHORITIES` - filter authorities
- `MORPH_EXPECT_BAD` - expected bad authorities
- `DEBUG` - debugging output
- `MORPH_PROCESSES` - number of parallel processes

## Performance Expectations

Typical performance improvements:
- **4 processes**: 3-4x faster
- **8 processes**: 6-7x faster (if you have the cores/bandwidth)
- **Diminishing returns** beyond 8 processes for most scrapers

Example: 20 authorities × 6 minutes each = 2 hours sequential → 30 minutes with 4 processes

## Debugging Parallel Scrapers

1. **Test with 1 process first**: `process_count: 1` to isolate logic issues
2. **Check individual authorities**: Use `MORPH_AUTHORITIES=problematic_auth`
3. **Monitor resource usage**: Watch CPU, memory, and network during runs
4. **Enable debugging**: `DEBUG=1` works in all processes

## Limitations

- **Shared state**: Each process is isolated - no shared variables between authorities
- **Memory usage**: Each process uses full memory - monitor total usage
- **Database locking**: Only the main process writes to SQLite (by design)
- **Error handling**: Exceptions in one process don't affect others

## Migration from Sequential

Your existing scraper logic requires minimal changes:
1. Extract single-authority logic into separate method
2. Add `collect_saves!` call at start of each subprocess
3. Return collected saves instead of direct database writes
4. Use `Parallel.map` instead of `each` for authorities

The core scraping logic in `YourScraper.scrape` remains completely unchanged.
