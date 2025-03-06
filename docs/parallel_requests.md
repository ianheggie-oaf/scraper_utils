# Parallel Request Processing

The ScraperUtils library provides a mechanism for executing HTTP requests in parallel while still maintaining the interleaved fiber-based scheduling system.

## Overview

When scraping multiple authority websites, network requests often become the bottleneck. While the `FiberScheduler` efficiently interleaves operations during delay periods, network requests still block a fiber until they complete.

The `ThreadScheduler` optimizes this process by:

1. Executing network requests in parallel using a thread pool
2. Allowing other fibers to continue working while waiting for responses
3. Integrating seamlessly with the existing `FiberScheduler`

## Key Components

### NetworkRequest

A value object encapsulating a network request:
- Fiber ID: Identifies which fiber made the request
- Client: The HTTP client to use (typically a Mechanize instance)
- Method: The operation to perform (e.g., :get, :post)
- Args: Arguments for the method

### NetworkResponse

A value object encapsulating a response:
- Fiber ID: Identifies which fiber should receive the response
- Result: The result of the operation
- Error: Any error that occurred
- Time Taken: Execution time in seconds

### ThreadScheduler

Manages a pool of threads that execute network requests:
- Processes requests from a queue
- Returns responses to the FiberScheduler
- Provides clear separation between network I/O and fiber scheduling

## Usage

```ruby
# In your authority scraper block
ScraperUtils::FiberScheduler.register_operation("authority_name") do
  # Instead of:
  # page = agent.get(url)
  
  # Use:
  page = ScraperUtils::FiberScheduler.queue_network_request(agent, :get, [url])
  
  # Process page as normal
  process_page(page)
end
```

## Configuration

The `ThreadScheduler` can be configured with different pool sizes:

```ruby
# Default is 20 threads
ScraperUtils::FiberScheduler.thread_scheduler.shutdown
ScraperUtils::FiberScheduler.instance_variable_set(
  :@thread_scheduler,
  ScraperUtils::ThreadScheduler.new(10) # Use 10 threads
)
```

## Benefits

1. **Improved Throughput**: Process multiple HTTP requests simultaneously
2. **Reduced Total Runtime**: Make better use of wait time during network operations
3. **Optimal Resource Usage**: Efficiently balance CPU and network operations
4. **Better Geolocation Handling**: Distribute requests across proxies more efficiently

## Debugging

When debugging issues with parallel requests, use:

```ruby
# Set debug level to see request/response logging
export DEBUG=2
```

The system will log:
- When requests are queued
- When responses are received
- How long each request took
- Any errors that occurred

## Implementation Details

The integration between `FiberScheduler` and `ThreadScheduler` follows these principles:

1. `FiberScheduler` maintains ownership of all fiber scheduling
2. `ThreadScheduler` only knows about requests and responses
3. Communication happens via value objects with validation
4. State is managed in dedicated `FiberState` objects
5. Each component has a single responsibility

This design provides a clean separation of concerns while enabling parallel network operations within the existing fiber scheduling framework.
