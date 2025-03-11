# frozen_string_literal: true

module ScraperUtils
  module Scheduler
    # Encapsulates a response from an asynchronous command execution
    class ThreadResponse
      # @return [Symbol] The authority from the original command
      attr_reader :authority

      # @return [Object, nil] The result of the command
      attr_reader :result

      # @return [Exception, nil] Any error that occurred during execution
      attr_reader :error

      # @return [Float] The time taken to execute the command in seconds
      attr_reader :time_taken

      # @return [Time, nil] Optionally delay the next process
      attr_accessor :delay_till

      # Initialize a new async response
      #
      # @param authority [Symbol] The authority from the original command
      # @param result [Object, nil] The result of the command
      # @param error [Exception, nil] Any error that occurred during execution
      # @param time_taken [Float] The time taken to submit_request the command in seconds
      def initialize(authority, result, error, time_taken)
        @authority = authority
        @result = result
        @error = error
        @time_taken = time_taken
        @delay_till = nil
      end

      # Check if the command execution was successful
      #
      # @return [Boolean] true if successful, false otherwise
      def success?
        @error.nil?
      end

      # Return result or raise error
      # @return [Object] Result pf request
      def result!
        return @result if success?
        raise @error
      end
    end
  end
end
