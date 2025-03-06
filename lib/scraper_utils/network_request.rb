# frozen_string_literal: true

module ScraperUtils
  # Encapsulates a network request to be executed by the ThreadScheduler
  class NetworkRequest
    # @return [Integer] The object_id of the fiber that made the request
    attr_reader :fiber_id
    
    # @return [Object] The client to use for the request (e.g., Mechanize instance)
    attr_reader :client
    
    # @return [Symbol] The method to call on the client (e.g., :get, :post)
    attr_reader :method
    
    # @return [Array] The arguments to pass to the method
    attr_reader :args
    
    # Initialize a new network request
    #
    # @param fiber_id [Integer] The object_id of the fiber that made the request
    # @param client [Object] The client to use for the request
    # @param method [Symbol] The method to call on the client
    # @param args [Array] The arguments to pass to the method
    # @raise [ArgumentError] If any required parameter is missing or invalid
    def initialize(fiber_id, client, method, args)
      @fiber_id = fiber_id
      @client = client
      @method = method
      @args = args
      
      validate!
    end
    
    private
    
    # Validate that all required parameters are present and valid
    #
    # @raise [ArgumentError] If any parameter is missing or invalid
    def validate!
      raise ArgumentError, "Fiber ID must be provided" unless @fiber_id
      raise ArgumentError, "Client must be provided" unless @client
      raise ArgumentError, "Method must be provided" unless @method
      raise ArgumentError, "Args must be an array" unless @args.is_a?(Array)
    end
  end
end
