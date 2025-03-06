# frozen_string_literal: true

module ScraperUtils
  # Encapsulates a response from a network request
  class NetworkResponse
    # @return [Integer] The object_id of the fiber that made the request
    attr_reader :fiber_id
    
    # @return [Object, nil] The result of the request
    attr_reader :result
    
    # @return [Exception, nil] Any error that occurred during the request
    attr_reader :error
    
    # @return [Float] The time taken to execute the request in seconds
    attr_reader :time_taken
    
    # Initialize a new network response
    #
    # @param fiber_id [Integer] The object_id of the fiber that made the request
    # @param result [Object, nil] The result of the request
    # @param error [Exception, nil] Any error that occurred during the request
    # @param time_taken [Float] The time taken to execute the request in seconds
    def initialize(fiber_id, result, error = nil, time_taken = 0)
      @fiber_id = fiber_id
      @result = result
      @error = error
      @time_taken = time_taken
    end
    
    # Check if the request was successful
    #
    # @return [Boolean] true if successful, false otherwise
    def success?
      @error.nil?
    end
  end
end
