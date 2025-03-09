# frozen_string_literal: true

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
      #
      # @return [ThreadResponse] The result of the request
      def execute
        super(:processed) do
          subject.send(method_name, *args)
        end
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
