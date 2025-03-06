# frozen_string_literal: true

module ScraperUtils
  # Executes HTTP requests in parallel using a thread pool while keeping
  # Mechanize client instances isolated to their original fibers.
  #
  # This class is designed to work with the existing fiber scheduling system
  # where fibers representing council site operations are scheduled based on
  # timestamps indicating when they should next run.
  #
  # @example Basic usage with get request in fiber scheduler
  #   executor = ScraperUtils::ThreadScheduler.new
  #   
  #   # Within a Fiber representing a council site
  #   command = {
  #     client: mechanize_client,
  #     method: :get,
  #     args: ["https://example.com"]
  #   }
  #   
  #   # Instead of delaying, request is executed in parallel
  #   fiber_data[:waiting_for_response] = true
  #   executor.queue_request(Fiber.current, command)
  #   Fiber.yield
  #   fiber_data[:waiting_for_response] = false
  #   
  #   # After yield, get result from fiber data
  #   result = fiber_data[:last_response]
  #   error = fiber_data[:last_error]
  #   time_taken = fiber_data[:last_request_time]
  #
  class ThreadScheduler
    # Initialize a new ThreadScheduler with a thread pool
    #
    # @param max_threads [Integer] The maximum number of threads in the pool
    # @param fiber_data_method [Symbol] Method to call on fiber to get its data (default: [])
    def initialize(max_threads = 10, fiber_data_method: nil)
      @request_queue = Queue.new
      @response_queue = Queue.new
      @running = true
      @fiber_data_method = fiber_data_method
      
      # Create worker threads
      @worker_threads = max_threads.times.map do
        Thread.new do
          while @running
            begin
              fiber, command = @request_queue.pop
              break unless @running
              
              start_time = Time.now
              
              begin
                result = execute_command(command)
                elapsed_time = Time.now - start_time
                @response_queue << [fiber, result, nil, elapsed_time]
              rescue => e
                elapsed_time = Time.now - start_time
                @response_queue << [fiber, nil, e, elapsed_time]
              end
            rescue => e
              # Log unhandled error
              puts "Worker thread error: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}" if $DEBUG
            end
          end
        end
      end
    end
    
    # Queue a request to be executed in parallel
    # The fiber will not be resumed automatically - the scheduler should check for completed requests
    #
    # @param fiber [Fiber] The fiber making the request
    # @param command [Hash] The command to execute
    # @option command [Object] :client The client to use (typically Mechanize instance)
    # @option command [Symbol] :method The method to call on the client (:get, :post, etc.)
    # @option command [Array] :args The arguments to pass to the method
    def queue_request(fiber, command)
      @request_queue << [fiber, command]
    end
    
    # Check for and process any completed requests
    # This should be called by the fiber scheduler
    #
    # @param timeout [Numeric, nil] Optional timeout in seconds to wait for a response
    # @return [Array, nil] Array of [fiber, processed] pairs if responses were processed, nil if none
    def process_responses(timeout = nil)
      result = nil
      
      # Try to process as many responses as available
      loop do
        begin
          # Non-blocking if timeout is nil, otherwise blocks with timeout
          fiber, response, error, time_taken = timeout ? @response_queue.pop(timeout) : @response_queue.pop(true)
          
          # Store result in fiber's data hash
          store_result_in_fiber(fiber, response, error, time_taken)
          
          # Track processed fibers
          result ||= []
          result << [fiber, true]
          
          # Reset timeout after first response
          timeout = nil
        rescue ThreadError
          # Queue is empty
          break
        end
      end
      
      result
    end
    
    # Check if there are any pending responses
    #
    # @return [Boolean] true if there are pending responses, false otherwise
    def responses_pending?
      !@response_queue.empty?
    end
    
    # Gracefully shut down the executor and all its threads
    #
    # @return [nil]
    def shutdown
      @running = false
      
      # Push dummy requests to unblock any waiting threads
      @worker_threads.size.times do
        @request_queue << [nil, nil]
      end
      
      # Wait for worker threads to finish processing
      @worker_threads.each(&:join)
      
      # Process any remaining responses
      process_responses(0.1)
      
      nil
    end
    
    private
    
    # Execute a command using the provided client
    #
    # @param command [Hash] The command to execute
    # @return [Object] The result of the command
    # @raise [ArgumentError] If the method is unknown
    def execute_command(command)
      return nil unless command
      
      client = command[:client]
      method = command[:method]
      args = command[:args]
      
      case method
      when :get
        client.get(*args)
      when :post
        client.post(*args)
      when :submit
        client.submit(*args)
      when :click
        client.click(*args)
      # Add other methods as needed
      else
        raise ArgumentError, "Unknown method: #{method}"
      end
    end
    
    # Store result in fiber's data hash
    #
    # @param fiber [Fiber] The fiber to store result for
    # @param result [Object, nil] The result of the command
    # @param error [Exception, nil] The error that occurred
    # @param time_taken [Float] The time taken to execute the command
    def store_result_in_fiber(fiber, result, error, time_taken)
      return unless fiber
      
      if @fiber_data_method
        # Use custom method to get fiber data
        data = fiber.send(@fiber_data_method)
      else
        # Use fiber instance variable if no method provided
        data = fiber.instance_variable_get(:@data) || {}
        fiber.instance_variable_set(:@data, data)
      end
      
      # Store result
      data[:last_response] = result
      data[:last_error] = error
      data[:last_request_time] = time_taken
      data[:response_ready] = true
    end
  end
end
