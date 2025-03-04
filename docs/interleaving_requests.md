# Interleaving Requests with FiberScheduler

The `ScraperUtils::FiberScheduler` provides a lightweight utility that:

* Works on other authorities while in the delay period for an authority's next request
* Optimizes the total scraper run time
* Allows you to increase the random delay for authorities without undue effect on total run time
* For the curious, it uses [ruby fibers](https://ruby-doc.org/core-2.5.8/Fiber.html) rather than threads as that is
  a simpler system and thus easier to get right, understand and debug!
* Cycles around the authorities when compliant_mode, max_load and random_delay are disabled

## Implementation

To enable fiber scheduling, change your scrape method to follow this pattern:

```ruby
def scrape(authorities, attempt)
  ScraperUtils::FiberScheduler.reset!
  exceptions = {}
  authorities.each do |authority_label|
    ScraperUtils::FiberScheduler.register_operation(authority_label) do
      ScraperUtils::FiberScheduler.log(
        "Collecting feed data for #{authority_label}, attempt: #{attempt}..."
      )
      ScraperUtils::DataQualityMonitor.start_authority(authority_label)
      YourScraper.scrape(authority_label) do |record|
        record["authority_label"] = authority_label.to_s
        ScraperUtils::DbUtils.save_record(record)
      rescue ScraperUtils::UnprocessableRecord => e
        ScraperUtils::DataQualityMonitor.log_unprocessable_record(e, record)
        exceptions[authority_label] = e
        # Continues processing other records
      end
    rescue StandardError => e
      warn "#{authority_label}: ERROR: #{e}"
      warn e.backtrace || "No backtrace available"
      exceptions[authority_label] = e
    end
    # end of register_operation block
  end
  ScraperUtils::FiberScheduler.run_all
  exceptions
end
```

## Logging with FiberScheduler

Use `ScraperUtils::FiberScheduler.log` instead of `puts` when logging within the authority processing code.
This will prefix the output lines with the authority name, which is needed since the system will interleave the work and
thus the output.

## Testing Considerations

This uses `ScraperUtils::RandomizeUtils` for determining the order of operations. Remember to add the following line to
`spec/spec_helper.rb`:

```ruby
ScraperUtils::RandomizeUtils.sequential = true
```

For full details, see the [FiberScheduler class documentation](https://rubydoc.info/gems/scraper_utils/ScraperUtils/FiberScheduler).
