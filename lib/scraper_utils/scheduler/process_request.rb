# frozen_string_literal: true

require_relative "thread_request"

module ScraperUtils
  module Scheduler
    # Encapsulates a request to be executed (usually )asynchronously by the ThreadPool)
    class ProcessRequest < ThreadRequest
      # @return [Object] The object to call the method on
      attr_reader :subject

      # @return [Symbol] The method to call on the subject
      attr_reader :method_name

      # @return [Array] The arguments to pass to the method
      attr_reader :args

      # Initialize a new async request
      #
      # @param authority [Symbol, nil] Authority for correlating requests and responses
      #   nil is used when threads are disabled to process locally without duplicating codd
      # @param subject [Object] The object to call the method on
      # @param method_name [Symbol] The method to call on the subject
      # @param args [Array] The arguments to pass to the method
      # @raise [ArgumentError] If any required parameter is missing or invalid
      def initialize(authority, subject, method_name, args)
        super(authority)
        @subject = subject
        @method_name = method_name
        @args = args

        validate!
      end

      # Execute the request by calling the method on the subject
      # If the subject has an instance variable @delay_till then that is added to the response
      # @return [ThreadResponse] The result of the request
      def execute
        result = execute_block do
          subject.send(method_name, *args)
        end
        result.delay_till = subject.instance_variable_get(:@delay_till)
        result
      end

      private

      # Validate that all required parameters are present and valid
      #
      # @raise [ArgumentError] If any parameter is missing or invalid
      def validate!
        raise ArgumentError, "Subject must be provided" unless @subject
        raise ArgumentError, "Method name must be provided" unless @method_name
        raise ArgumentError, "Args must be an array" unless @args.is_a?(Array)
        raise ArgumentError, "Subject must respond to method" unless @subject&.respond_to?(@method_name)
      end
    end
  end
end
