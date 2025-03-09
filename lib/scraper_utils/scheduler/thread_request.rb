# frozen_string_literal: true

require_relative "thread_response"

module ScraperUtils
  module Scheduler
    # Encapsulates a request to be executed (usually) asynchronously by the ThreadPool
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

      # Execute the request by calling the block
      #
      # @return [ThreadResponse] The result of the request
      def execute(response_type)
        start_time = Time.now
        begin
          result = yield
          elapsed_time = Time.now - start_time
          ThreadResponse.new(
            authority,
            response_type,
            result,
            nil,
            elapsed_time
          )
        rescue => e
          elapsed_time = Time.now - start_time
          ThreadResponse.new(
            authority,
            response_type,
            nil,
            e,
            elapsed_time
          )
        end
      end

      # Validate that all required parameters are present and valid
      #
      # @raise [ArgumentError] If any parameter is missing or invalid
      def validate!
        raise ArgumentError, "Authority must be provided" unless @authority
      end
    end
  end
end
