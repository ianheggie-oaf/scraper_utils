Parallel Request Processing
===========================

The ScraperUtils library provides a mechanism for executing network I/O requests in parallel using a thread for each
operation worker, allowing the fiber to yield control and allow other fibers to process whilst the thread processes the
mechanize network I/O request.

This can be disabled by setting `MORPH_DISABLE_THREADS` ENV var to a non-blank value.

Overview
--------

When scraping multiple authority websites, around 99% of the time was spent waiting for network I/O. While the
`Scheduler`
efficiently interleaves fibers during delay periods, network I/O requests will still block a fiber until they
complete.

The `OperationWorker` optimizes this process by:

1. Executing mechanize network operations in parallel using a thread for each operation_worker and fiber
2. Allowing other fibers to continue working while waiting for thread responses
3. Integrating seamlessly with the existing `Scheduler`

Usage
-----

```ruby
# In your authority scraper block
ScraperUtils::Scheduler.register_operation("authority_name") do
  # Instead of:
  # page = agent.get(url)

  # Use:
  page = ScraperUtils::Scheduler.execute_request(agent, :get, [url])

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
command = ScraperUtils::ProcessRequest.new(
  "test_id",
  test_object,
  :sleep_test,
  [0.5]
)

thread_scheduler.queue_request(command)
```

Configuration
-------------

The followingENV variables affect how `Scheduler` is configured:

* `MORPH_DISABLE_THREADS=1` disabled the use of threads
* `MORPH_MAX_WORKERS=N` configures the system to a max of N workers (minimum 1).
  If N is 1 then this forces the system to process one authority at a time.

Key Components
--------------

### ThreadRequest

A value object encapsulating a command to be executed:

- External ID: Any value suitable as a hash key (String, Symbol, Integer, Object) that identifies the command
- Subject: The object to call the method on
- Method: The method to call on the subject
- Args: Arguments to pass to the method

### ThreadResponse

A value object encapsulating a response:

- External ID: Matches the ID from the original command
- Result: The result of the operation
- Error: Any error that occurred
- Time Taken: Execution time in seconds

### ThreadPool

Manages a pool of threads that execute commands:

- Processes commands from a queue
- Returns responses with matching external IDs
- Provides clear separation between I/O and scheduling

Benefits
--------

1. **Improved Throughput**: Process multiple operations simultaneously
2. **Reduced Total Runtime**: Make better use of wait time during network operations
3. **Optimal Resource Usage**: Efficiently balance CPU and network operations
4. **Better Geolocation Handling**: Distribute requests across proxies more efficiently
5. **Testability**: Execute non-network operations for testing concurrency

Debugging
---------

When debugging issues with parallel operations, use:

```shell
# Set debug level to see request/response logging
export DEBUG = 2
```

The system will log:

- When commands are queued
- When responses are received
- How long each operation took
- Any errors that occurred

## Implementation Details

The integration between `Scheduler` and `ThreadPool` follows these principles:

1. `Scheduler` maintains ownership of all fiber scheduling
2. `ThreadPool` only knows about commands and responses
3. Communication happens via value objects with validation
4. State is managed in dedicated `FiberState` objects
5. Each component has a single responsibility

This design provides a clean separation of concerns while enabling parallel operations within the existing fiber
scheduling framework.
