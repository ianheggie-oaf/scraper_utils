# frozen_string_literal: true

module ScraperUtils
  module Scheduler
    # Encapsulates a request to be executed (usually )asynchronously by the ThreadPool)
    class DelayRequest < ThreadRequest
      # @return [Time] The time to delay till
      attr_reader :delay_till

      # Initialize a new delay request
      #
      # @param authority [Symbol] Authority for correlating requests and responses
      # @param delay_till [Time] The time to delay till
      # @raise [ArgumentError] If any required parameter is missing or invalid
      def initialize(authority, delay_till)
        super(authority)
        @delay_till = delay_till

        validate!
      end

      # Execute the request by calling the method on the subject
      #
      # @return [ThreadResponse] The result of the request
      def execute
        super(:delayed) do
          seconds = (Time.now - @delay_till).to_f
          seconds.positive? ? sleep(seconds) : 0
        end
      end

      private

      # Validate that all required parameters are present and valid
      #
      # @raise [ArgumentError] If any parameter is missing or invalid
      def validate!
        raise ArgumentError, "Delay Till must be provided" unless @delay_till
      end
    end
  end
end
