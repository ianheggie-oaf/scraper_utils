# frozen_string_literal: true

require_relative "network_request"
require_relative "network_response"

module ScraperUtils
  # Executes HTTP requests in parallel using a thread pool while keeping
  # Mechanize client instances isolated to their original fibers.
  #
  # @example Basic usage
  #   executor = ScraperUtils::ThreadScheduler.new
  #   
  #   # Create a request
  #   request = ScraperUtils::NetworkRequest.new(
  #     fiber_id,
  #     mechanize_client,
  #     :get,
  #     ["https://example.com"]
  #   )
  #   
  #   # Queue the request
  #   executor.queue_request(request)
  #   
  #   # Later, process responses
  #   responses = executor.process_responses
  #   
  #   # Each response is a NetworkResponse
  #   responses.each do |response|
  #     if response.success?
  #       process_result(response.result)
  #     else
  #       handle_error(response.error)
  #     end
  #   end
  class ThreadScheduler
    # Initialize a new ThreadScheduler with a thread pool
    #
    # @param max_threads [Integer] The maximum number of threads in the pool
    def initialize(max_threads = 20)
      @request_queue = Queue.new
      @response_queue = Queue.new
      @running = true
      
      # Create worker threads
      @worker_threads = max_threads.times.map do
        Thread.new do
          while @running
            begin
              request = @request_queue.pop
              break unless @running

              if request
                start_time = Time.now
                
                begin
                  result = execute_request(request)
                  elapsed_time = Time.now - start_time
                  @response_queue << NetworkResponse.new(
                    request.fiber_id, 
                    result, 
                    nil,
                    elapsed_time
                  )
                rescue => e
                  elapsed_time = Time.now - start_time
                  @response_queue << NetworkResponse.new(
                    request.fiber_id,
                    nil,
                    e,
                    elapsed_time
                  )
                end
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
    #
    # @param request [NetworkRequest] The request to execute
    # @return [nil]
    def queue_request(request)
      @request_queue << request
      nil
    end
    
    # Check for and process any completed requests
    #
    # @param timeout [Numeric, nil] Optional timeout in seconds to wait for a response
    # @return [Array<NetworkResponse>] Array of responses or empty array if none
    def process_responses(timeout = nil)
      results = []
      
      # Try to process as many responses as available
      loop do
        begin
          # Non-blocking if timeout is nil or 0, otherwise blocks with timeout
          response = if timeout && timeout > 0
                       @response_queue.pop(timeout)
                     else
                       @response_queue.pop(true)
                     end
          
          results << response
          
          # Reset timeout after first response to process remaining immediately
          timeout = nil
        rescue ThreadError
          # Queue is empty
          break
        end
      end
      
      results
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
      
      # Push nil requests to unblock any waiting threads
      @worker_threads.size.times do
        @request_queue << nil
      end
      
      # Wait for worker threads to finish processing
      @worker_threads.each(&:join)
      
      # Process any remaining responses
      process_responses(0.1)
      
      nil
    end
    
    private
    
    # Execute a request using the provided client
    #
    # @param request [NetworkRequest] The request to execute
    # @return [Object] The result of the request
    # @raise [ArgumentError] If the method is unknown
    def execute_request(request)
      client = request.client
      method = request.method
      args = request.args
      
      case method
      when :get
        client.get(*args)
      when :post
        client.post(*args)
      when :submit
        client.submit(*args)
      when :click
        client.click(*args)
      when :test_sleep
        # Special method for testing thread concurrency
        sleep_duration = args.first || 0.2
        IO.popen("sleep #{sleep_duration}", "r").read
        "Slept for #{sleep_duration} seconds"
      else
        raise ArgumentError, "Unknown method: #{method}"
      end
    end
  end
end
