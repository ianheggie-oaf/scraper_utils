# frozen_string_literal: true

module ScraperUtils
  # Encapsulates a response from an asynchronous command execution
  class AsyncResponse
    # @return [Object] The identifier from the original command
    attr_reader :external_id
    
    # @return [Object, nil] The result of the command
    attr_reader :result
    
    # @return [Exception, nil] Any error that occurred during execution
    attr_reader :error
    
    # @return [Float] The time taken to enqueue_command the command in seconds
    attr_reader :time_taken
    
    # Initialize a new async response
    #
    # @param external_id [Object] The identifier from the original command
    # @param result [Object, nil] The result of the command
    # @param error [Exception, nil] Any error that occurred during execution
    # @param time_taken [Float] The time taken to enqueue_command the command in seconds
    def initialize(external_id, result, error = nil, time_taken = 0)
      @external_id = external_id
      @result = result
      @error = error
      @time_taken = time_taken
    end
    
    # Check if the command execution was successful
    #
    # @return [Boolean] true if successful, false otherwise
    def success?
      @error.nil?
    end
  end
end
