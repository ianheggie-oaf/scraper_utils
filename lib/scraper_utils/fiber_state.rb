# frozen_string_literal: true

module ScraperUtils
  # Encapsulates the state of a Fiber managed by FiberScheduler
  class FiberState
    # @return [Integer] The object_id of the fiber
    attr_reader :external_id
    
    # @return [String] The authority name associated with this fiber
    attr_reader :authority
    
    # @return [Time, nil] When the fiber should be resumed
    attr_accessor :resume_at
    
    # @return [Object, nil] The response from a network request
    attr_accessor :response
    
    # @return [Exception, nil] Any error that occurred during a network request
    attr_accessor :error
    
    # Initialize a new fiber state
    #
    # @param fiber_id [Integer] The object_id of the fiber
    # @param authority [String] The authority name associated with this fiber
    def initialize(fiber_id, authority)
      @external_id = fiber_id
      @authority = authority
      @resume_at = nil
      @waiting_for_response = false
      @response = nil
      @error = nil
    end
    
    # Check if the fiber is waiting for a command response
    #
    # @return [Boolean] true if waiting, false otherwise
    def waiting_for_response?
      @waiting_for_response
    end
    
    # Set whether the fiber is waiting for a command response
    #
    # @param value [Boolean] true if waiting, false otherwise
    # @return [Boolean] the new waiting status
    def waiting_for_response=(value)
      @waiting_for_response = !!value
    end
    
    # Check if the fiber has a response ready to be processed
    #
    # @return [Boolean] true if response ready, false otherwise
    def response_ready?
      !waiting_for_response? && !@response.nil?
    end
    
    # Check if the fiber is ready to run based on either response or time
    #
    # @param current_time [Time] The current time
    # @return [Boolean] true if ready to run, false otherwise
    def ready_to_run?(current_time)
      response_ready? || (resume_at && resume_at <= current_time)
    end
  end
end
