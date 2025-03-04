# Randomizing Requests

`ScraperUtils::RandomizeUtils` provides utilities for randomizing processing order in scrapers,
which is helpful for distributing load and avoiding predictable patterns.

## Basic Usage

Pass a `Collection` or `Array` to `ScraperUtils::RandomizeUtils.randomize_order` to randomize it in production, but
receive it as is when testing.

```ruby
# Randomize a collection
randomized_authorities = ScraperUtils::RandomizeUtils.randomize_order(authorities)

# Use with a list of records from an index to randomize requests for details
records.each do |record|
  # Process record
end
```

## Testing Configuration

Enforce sequential mode when testing by adding the following code to `spec/spec_helper.rb`:

```ruby
ScraperUtils::RandomizeUtils.sequential = true
```

## Notes

* You can also force sequential mode by setting the env variable `MORPH_PROCESS_SEQUENTIALLY` to `1` (any non-blank value)
* Testing using VCR requires sequential mode

For full details, see the [RandomizeUtils class documentation](https://rubydoc.info/gems/scraper_utils/ScraperUtils/RandomizeUtils).
