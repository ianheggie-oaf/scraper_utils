# Debugging Techniques

ScraperUtils provides several debugging utilities to help you troubleshoot your scrapers.

## Enabling Debug Mode

Set the `DEBUG` environment variable to enable debugging:

```bash
export DEBUG=1  # Basic debugging
export DEBUG=2  # Verbose debugging
export DEBUG=3  # Trace debugging with detailed content
```

## Debug Utilities

The `ScraperUtils::DebugUtils` module provides several methods for debugging:

```ruby
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

## Debug Level Constants

- `DISABLED_LEVEL = 0`: Debugging disabled
- `BASIC_LEVEL = 1`: Basic debugging information
- `VERBOSE_LEVEL = 2`: Verbose debugging information
- `TRACE_LEVEL = 3`: Detailed tracing information

## Helper Methods

- `debug_level`: Get the current debug level
- `debug?(level)`: Check if debugging is enabled at the specified level
- `basic?`: Check if basic debugging is enabled
- `verbose?`: Check if verbose debugging is enabled
- `trace?`: Check if trace debugging is enabled

For full details, see the [DebugUtils class documentation](https://rubydoc.info/gems/scraper_utils/ScraperUtils/DebugUtils).
