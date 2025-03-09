# frozen_string_literal: true

module ScraperUtils
  module Scheduler
    # Encapsulates the state of a registered operation managed by FiberScheduler
    class FiberOperation
      class NotReadyError < RuntimeError; end

      # @return [Fiber] The fiber
      attr_reader :fiber

      # @return [Symbol] The authority name associated with this fiber
      attr_reader :authority

      # @return [Time] When the fiber should be delayed till / ready to resume at
      attr_accessor :resume_at

      # @return [Symbol] The type to be passed to the next resume, one of [:start, :abort, :delayed, :processed, :finished]
      attr_accessor :resume_type

      # @return [ThreadResponse, nil] The response from a process or delay request, passed as second arg on the next resume
      attr_accessor :response

      def self.next_resume_at
        @next_resume_at = [@next_resume_at, Time.now - 0.01].compact.max + 0.01
      end

      # Initialize a new fiber state
      # @param fiber [Fiver] Fiber to process authority
      # @param authority [Symbol] Authority label
      def initialize(fiber, authority)
        @fiber = fiber
        @authority = authority
        @resume_type = :start
        # when ready to resume
        @resume_at = self.class.next_resume_at
        # state for @resume_type == :process
        # waiting got response from thread
        @waiting_for_response = false
        # response from thread or delay
        @response = nil
        raise(ArgumentError, "Fiber and Authority must be provided") unless fiber && authority
      end

      def alive?
        resume_type != :finished && fiber.alive?
      end

      # Check if the fiber is ready to run based on response to request
      #
      # @return [Boolean] true if we can resume the fiber, false otherwise
      def ready_to_run?
        case @resume_type
        when :finished then false
        when :delayed then @resume_at >= Time.now
        when :processed then @waiting_for_response
        else
          # :start, :abort
          true
        end
      end

      # Resume an operation that is ready to run, passing back the results from the last yielded request
      #
      # @return [ThreadRequest] Next request to be scheduled
      def resume
        raise ClosedQueueError unless alive?
        raise NotReadyError, "Cannot resume operation for #{authority} till ready to run!" unless ready_to_run?

        @fiber.resume @resume_type, @response
      end

      # Shutdown fiber
      # if the fiber is alive and not the current fiber, then the fiber is resumed with an abort request
      def shutdown
        @resume_type = (@fiber.alive? && Fiber.current.object_id != @fiber.object_id) ? :abort : :finished
        @resume_at = self.class.next_resume_at
        @response = nil
        @waiting_for_response = false
        # Allow fiber to clean up its resources
        resume if alive? && Fiber.current.object_id != @fiber.object_id
      end

      def process_thread_response(response)
        @response = response
        @waiting_for_response = false
        @resume_at = Time.now
        if DebugUtils.basic?
          log "Received response from thread for fiber #{response.authority} in #{response.time_taken.round(3)}s"
        end
      end


      # Check if the fiber is waiting for a command response from a thread
    #
    # @return [Boolean] true if waiting, false otherwise
    # def waiting_for_response?
    #   @waiting_for_response
    # end

    # Set the fiber into waiting for response mode once request is queued for thread
    # def waiting_for_response!
    #   raise "Last response has to be picked up first!" if @waiting_for_response
    #   @waiting_for_response = true
    # end

    # Pickup response and clear waiting_for_response
    # @return [Object] response from thread
    # def pick_up_response
    #   raise "No response ready to pickup!" unless response_ready?
    #
    #   @waiting_for_response = false
    #   raise(@error) if @error
    #
    #   # release reference to response so it can be garbage collected
    #   this_response, @response = @response, nil
    #   this_response
    # end
  end
end
end
