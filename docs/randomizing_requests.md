Randomizing Requests
====================

`ScraperUtils::RandomizeUtils` provides utilities for randomizing processing order in scrapers,
which is helpful for distributing load and avoiding predictable patterns.

Usage
-----

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

Testing Configuration
---------------------

Enforce sequential mode when testing by adding the following code to `spec/spec_helper.rb`:

```ruby
ScraperUtils::RandomizeUtils.random = false
```

Notes
-----

* You can also disable random mode by setting the env variable `MORPH_DISABLE_RANDOM` to `1` (or any non-blank value)
* Testing using VCR requires random to be disabled

For full details, see {ScraperUtils::RandomizeUtils Randomize Utils class documentation}
