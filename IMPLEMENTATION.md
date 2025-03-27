IMPLEMENTATION
==============

Document decisions on how we are implementing the specs to be consistent and save time.
Things we MUST do go in SPECS.
Choices between a number of valid possibilities go here. 
Once made, these choices should only be changed after careful consideration.

ASK for clarification of any apparent conflicts with SPECS, GUIDELINES or project instructions.

## Debugging

Output debugging messages if ENV['DEBUG'] is set, for example:

```ruby
puts "Pre Connect request: #{request.inspect}" if ENV["DEBUG"]
```

## Robots.txt Handling

- Used as a "good citizen" mechanism for respecting site preferences
- Graceful fallback (to permitted) if robots.txt is unavailable or invalid
- Match `/^User-agent:\s*ScraperUtils/i` for specific user agent
  - If there is a line matching `/^Disallow:\s*\//` then we are disallowed
  - Check for `/^Crawl-delay:\s*(\d[.0-9]*)/` to extract delay
- If the no crawl-delay is found in that section, then check in the default `/^User-agent:\s*\*/` section
- This is a deliberate significant simplification of the robots.txt specification in RFC 9309.

## Method Organization

- Externalize configuration to improve testability
- Keep shared logic in the main class
- Decisions / information specific to just one class, can be documented there, otherwise it belongs here

## Testing Directory Structure

Our test directory structure reflects various testing strategies and aspects of the codebase:

### API Context Directories
- `spec/scraper_utils/fiber_api/` - Tests functionality called from within worker fibers
- `spec/scraper_utils/main_fiber/` - Tests functionality called from the main fiber's perspective
- `spec/scraper_utils/thread_api/` - Tests functionality called from within worker threads

### Utility Classes
- `spec/scraper_utils/mechanize_utils/` - Tests for `lib/scraper_utils/mechanize_utils/*.rb` files
- `spec/scraper_utils/scheduler/` - Tests for `lib/scraper_utils/scheduler/*.rb` files
- `spec/scraper_utils/scheduler2/` - FIXME: remove duplicate tests and merge to `spec/scraper_utils/scheduler/` unless > 200 lines

### Integration vs Unit Tests
- `spec/scraper_utils/integration/` - Tests that focus on the integration between components
  - Name tests after the most "parent-like" class of the components involved

### Special Configuration Directories
These specs check the options we use when things go wrong in production

- `spec/scraper_utils/no_threads/` - Tests with threads disabled (`MORPH_DISABLE_THREADS=1`)
- `spec/scraper_utils/no_fibers/` - Tests with fibers disabled (`MORPH_MAX_WORKERS=0`)
- `spec/scraper_utils/sequential/` - Tests with exactly one worker (`MORPH_MAX_WORKERS=1`)

### Directories to break up large specs
Keep specs less than 200 lines long

- `spec/scraper_utils/replacements` - Tests for replacements in MechanizeActions
- `spec/scraper_utils/replacements2` - FIXME: remove duplicate tests and merge to `spec/scraper_utils/replacements/`?
- `spec/scraper_utils/selectors` - Tests the various node selectors available in MechanizeActions
- `spec/scraper_utils/selectors2` - FIXME: remove duplicate tests and merge to `spec/scraper_utils/selectors/`?

### General Testing Guidelines
- Respect fiber and thread context validation - never mock the objects under test
- Structure tests to run in the appropriate fiber context
- Use real fibers, threads and operations rather than excessive mocking
- Ensure proper cleanup of resources in both success and error paths
- ASK when unsure which (yard doc, spec or code) is wrong as I don't always follow the "write specs first" strategy
