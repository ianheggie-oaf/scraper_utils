# frozen_string_literal: true

require_relative "thread_request"
require_relative "thread_response"

module ScraperUtils
  module Scheduler
    # Executes commands in parallel using a thread pool
    #
    # @example Basic usage
    #   pool = ScraperUtils::ThreadPool.new
    #
    #   # Create a request
    #   request = ScraperUtils::ThreadRequest.new(
    #     operation_id,
    #     mechanize_client,
    #     :get,
    #     ["https://example.com"]
    #   )
    #
    #   # Queue the request
    #   executor.queue_request(request)
    #
    #   # Later, process responses
    #   response = executor.get_response(operation_id)
    #
    #   # Each response is an AsyncResponse
    #   if response.success?
    #     process_result(response.result)
    #   else
    #     handle_error(response.error)
    #   end
    #
    class ThreadPool
      # @!group PublicApi

      # Initialize a new ThreadPool with a thread pool
      #
      # @param max_threads [Integer] The maximum number of threads in the pool
      def initialize(max_threads = 50)
        @request_queue = Queue.new
        @response_queue = Queue.new

        # Create worker threads
        @threads = max_threads.times.map do
          Thread.new do
            Thread.current[:current_authority] = nil
            while (request = @request_queue.pop)
              begin
                Thread.current[:current_authority] = request.authority
                @response_queue.push request.execute
              ensure
                Thread.current[:current_authority] = nil
              end
            end
          end
        end
      end

      # Queue a thread request to be executed in parallel
      #
      # @param request [ThreadRequest] The request to submit_request
      # @return [nil]
      def submit_request(request)
        @request_queue.push request
        nil
      end

      # Return the next response, returns nil if queue is empty
      #
      # @return [ThreadResponse, nil] Result of request execution
      def get_response(non_block = true)
        return nil if non_block && @response_queue.empty?

        @response_queue.pop(non_block)
      end

      # Gracefully shut down the executor and all its threads
      #
      # @return [Array<ThreadResponse>] Returns remaining responses
      def shutdown
        # Signal threads to finish processing
        @request_queue.close

        # Wait for worker threads to finish processing
        @threads.each(&:join)

        # collect remaining results
        results = []
        while (response = get_response)
          results << response
        end

        @response_queue.close
        results
      end

      # Return current authority
      def current_authority
        Thread.current[:current_authority]
      end


    end
  end
end
