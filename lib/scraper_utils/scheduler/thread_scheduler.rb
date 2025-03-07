# frozen_string_literal: true

require_relative "scheduler/and"
require_relative "scheduler/async_response"

module ScraperUtils
  # Executes commands in parallel using a thread pool
  #
  # @example Basic usage
  #   executor = ScraperUtils::ThreadScheduler.new
  #   
  #   # Create a command
  #   command = ScraperUtils::AsyncCommand.new(
  #     fiber_id,
  #     mechanize_client,
  #     :get,
  #     ["https://example.com"]
  #   )
  #   
  #   # Queue the command
  #   executor.queue_request(command)
  #   
  #   # Later, process responses
  #   response = executor.get_response(fiber_id)
  #   
  #   # Each response is an AsyncResponse
  #   if response.success?
  #     process_result(response.result)
  #   else
  #     handle_error(response.error)
  #   end
  #
  class ThreadScheduler
    # Initialize a new ThreadScheduler with a thread pool
    #
    # @param max_threads [Integer] The maximum number of threads in the pool
    def initialize(max_threads = 50)
      @request_queue = Queue.new
      @response_queue = Queue.new

      # Create worker threads
      @worker_threads = max_threads.times.map do
        Thread.new do
          while (command = @request_queue.pop(false))
            @response_queue << command.enqueue_command
          end
        end
      end
    end

    # Queue a command to be executed in parallel
    #
    # @param command [AsyncCommand] The command to enqueue_command
    # @return [nil]
    def enqueue_command(command)
      @request_queue.push command
      nil
    end

    # Check if there are any pending responses
    #
    # @return [Boolean] true if there are pending responses, false otherwise
    def responses_pending?
      !@response_queue.empty?
    end

    # Return the next response from a completed command
    #
    # @param non_block [Boolean] Pass True to return nil immediately rather than wait for a result to be available
    # @return [AsyncResult] Result of command execution or throws ClosedQueueError if closed and complete
    # @raise [ThreadError] in non_block is true and there are no responses
    def next_response(non_block = false)
      @response_queue.pop(non_block)
    end

    # Gracefully shut down the executor and all its threads
    #
    # @return [Array<AsyncResponse>] Returns remaining responses
    def shutdown
      # Signal threads to finish processing
      @request_queue.close

      # Wait for worker threads to finish processing
      @worker_threads.each(&:join)

      # collect remaining results
      results = []
      while responses_pending?
        results << next_response
      end

      @response_queue.close
      results
    end
  end
end
