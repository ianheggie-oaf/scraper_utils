# frozen_string_literal: true

require_relative "thread_response"

module ScraperUtils
  module Scheduler
    # Encapsulates a request that pushed to the fiber's request queue to be executed by the Fiber's Thread
    # The response is returned via the Scheduler's response queue
    # @see {ProcessRequest}
    # @see {DelayRequest}
    class ThreadRequest
      # @return [Symbol] Authority for correlating requests and responses
      attr_reader :authority

      # Initialize a new process request
      #
      # @param authority [Symbol, nil] Authority for correlating requests and responses
      def initialize(authority)
        @authority = authority
      end

      # Execute a request by calling the block
      # @param resume_state [Symbol] Resume type to construct ThreadResponse with
      # @return [ThreadResponse] The result of the request
      def execute_block
        start_time = Time.now
        begin
          result = yield
          elapsed_time = Time.now - start_time
          ThreadResponse.new(
            authority,
            result,
            nil,
            elapsed_time
          )
        rescue => e
          elapsed_time = Time.now - start_time
          ThreadResponse.new(
            authority,
            nil,
            e,
            elapsed_time
          )
        end
      end
    end
  end
end
