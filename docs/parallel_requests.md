# Parallel Request Processing

The ScraperUtils library provides a mechanism for executing operations in parallel using a thread pool, while still maintaining the interleaved fiber-based scheduling system.

## Overview

When scraping multiple authority websites, network requests often become the bottleneck. While the `FiberScheduler` efficiently interleaves operations during delay periods, network requests still block a fiber until they complete.

The `ThreadScheduler` optimizes this process by:

1. Executing operations in parallel using a thread pool
2. Allowing other fibers to continue working while waiting for responses
3. Integrating seamlessly with the existing `FiberScheduler`

## Key Components

### AsyncCommand

A value object encapsulating a command to be executed:
- External ID: Any value suitable as a hash key (String, Symbol, Integer, Object) that identifies the command
- Subject: The object to call the method on
- Method: The method to call on the subject
- Args: Arguments to pass to the method

### AsyncResponse

A value object encapsulating a response:
- External ID: Matches the ID from the original command
- Result: The result of the operation
- Error: Any error that occurred
- Time Taken: Execution time in seconds

### ThreadScheduler

Manages a pool of threads that execute commands:
- Processes commands from a queue
- Returns responses with matching external IDs
- Provides clear separation between I/O and scheduling

## Usage

```ruby
# In your authority scraper block
ScraperUtils::Scheduler.register_operation("authority_name") do
  # Instead of:
  # page = agent.get(url)

  # Use:
  page = ScraperUtils::Scheduler.queue_network_request(agent, :get, [url])

  # Process page as normal
  process_page(page)
end
```

For testing purposes, you can also execute non-network operations:

```ruby
# Create a test object
test_object = Object.new
def test_object.sleep_test(duration)
  sleep(duration)
  "Completed after #{duration} seconds"
end

# Queue a sleep command
command = ScraperUtils::AsyncCommand.new(
  "test_id",
  test_object,
  :sleep_test,
  [0.5]
)

thread_scheduler.queue_request(command)
```

## Configuration

The `ThreadScheduler` can be configured with different pool sizes:

```ruby
# Default is 20 threads
ScraperUtils::Scheduler.thread_scheduler.shutdown
ScraperUtils::Scheduler.instance_variable_set(
  :@thread_scheduler,
  ScraperUtils::ThreadScheduler.new(10) # Use 10 threads
)
```

## Benefits

1. **Improved Throughput**: Process multiple operations simultaneously
2. **Reduced Total Runtime**: Make better use of wait time during network operations
3. **Optimal Resource Usage**: Efficiently balance CPU and network operations
4. **Better Geolocation Handling**: Distribute requests across proxies more efficiently
5. **Testability**: Execute non-network operations for testing concurrency

## Debugging

When debugging issues with parallel operations, use:

```ruby
# Set debug level to see request/response logging
export DEBUG=2
```

The system will log:
- When commands are queued
- When responses are received
- How long each operation took
- Any errors that occurred

## Implementation Details

The integration between `FiberScheduler` and `ThreadScheduler` follows these principles:

1. `FiberScheduler` maintains ownership of all fiber scheduling
2. `ThreadScheduler` only knows about commands and responses
3. Communication happens via value objects with validation
4. State is managed in dedicated `FiberState` objects
5. Each component has a single responsibility

This design provides a clean separation of concerns while enabling parallel operations within the existing fiber scheduling framework.
