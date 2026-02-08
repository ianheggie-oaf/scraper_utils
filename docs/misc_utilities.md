# Misc Utilities

## Throttling Requests

Use `ScraperUtils::MiscUtils.throttle_block` to automatically pace requests based on server response time:

```ruby
response = ScraperUtils::MiscUtils.throttle_block do
  HTTParty.get(url)
end
# process response
```

The throttle automatically:

- Measures block execution time
- Adds 0.5s delay (configurable via `extra_delay:`)
- Pauses before next request based on previous timing
- Caps pause at 120s maximum

Override the next pause duration manually if needed:

```ruby
ScraperUtils::MiscUtils.pause_duration = 2.0
```

**Note:** the agent returned by `ScraperUtils::MechanizeUtils.mechanize_agent` automatically applies throttling when
each request is made and thus does not need to be wrapped with the helper.
