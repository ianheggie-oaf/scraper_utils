# frozen_string_literal: true

module ScraperUtils
  # Encapsulates a command to be executed (usually )asynchronously by the ThreadScheduler)
  class AsyncCommand
    # @return [Object] An identifier for correlating commands and responses
    # Can be any value suitable as a hash key (typically a Symbol, String, or Integer)
    attr_reader :external_id
    
    # @return [Object] The object to call the method on
    attr_reader :subject
    
    # @return [Symbol] The method to call on the subject
    attr_reader :method_name
    
    # @return [Array] The arguments to pass to the method
    attr_reader :args
    
    # Initialize a new async command
    #
    # @param external_id [Object] An identifier for correlating commands and responses
    # @param subject [Object] The object to call the method on
    # @param method_name [Symbol] The method to call on the subject
    # @param args [Array] The arguments to pass to the method
    # @raise [ArgumentError] If any required parameter is missing or invalid
    def initialize(external_id, subject, method_name, args)
      @external_id = external_id
      @subject = subject
      @method_name = method_name
      @args = args
      
      validate!
    end

    # Execute the command by calling the method on the subject
    #
    # @return [AsyncResponse] The result of the command
    def execute
      start_time = Time.now
      begin
        result = subject.send(method_name, *args)
        elapsed_time = Time.now - start_time
        AsyncResponse.new(
          external_id,
          result,
          nil,
          elapsed_time
        )
      rescue => e
        elapsed_time = Time.now - start_time
        AsyncResponse.new(
          external_id,
          nil,
          e,
          elapsed_time
        )
      end
    end
    
    private
    
    # Validate that all required parameters are present and valid
    #
    # @raise [ArgumentError] If any parameter is missing or invalid
    def validate!
      raise ArgumentError, "External ID must be provided" unless @external_id
      raise ArgumentError, "Subject must be provided" unless @subject
      raise ArgumentError, "Method name must be provided" unless @method_name
      raise ArgumentError, "Args must be an array" unless @args.is_a?(Array)
      raise ArgumentError, "Subject must respond to method" unless @subject&.respond_to?(@method_name)
    end
  end
end
