# frozen_string_literal: true

require_relative "constants"
require_relative 'process_request'

module ScraperUtils
  module Scheduler
    # Handles the processing of a registered operation and associated fiber and thread state
    class OperationWorker

      class NotReadyError < RuntimeError; end

      # @return [Fiber] The fiber
      attr_reader :fiber

      # @return [Symbol] The authority name associated with this fiber
      attr_reader :authority

      # @return [Time] When the fiber should be delayed till / ready to resume at
      attr_accessor :resume_at

      # @return [ThreadResponse, nil] The response to be passed on the next resume
      attr_accessor :response

      # @return [Boolean] Waiting for a response
      attr_reader :waiting_for_response

      # @return [Thread] Thread used
      attr_reader :thread

      # @return [Thread::Queue] The request queue for the thread
      attr_reader :request_queue

      def self.next_resume_at
        @next_resume_at = [@next_resume_at, Time.now - 0.001].compact.max + 0.001
      end

      # Fiber has not finished running
      def alive?
        fiber.alive?
      end

      # Worker has the necessary state to be resumed
      def can_resume?
        !@response.nil? && !@resume_at.nil? && alive?
      end

      # Save thread response from main or worker fiber
      def save_thread_response(response)
        raise "#{authority} Wasn't waiting for response! Got: #{response.inspect}" unless @waiting_for_response
        @response = response
        @waiting_for_response = false
        @resume_at = [response&.delay_till, Time.now].compact.max
        if DebugUtils.basic?
          log "Received #{response&.class&.name || 'nil response'} from thread for fiber #{authority} in #{response&.time_taken&.round(3)}s"
        end
        response
      end

      # close resources from worker fiber
      # Called by worker fiber just before it exits
      def close
        validate_fiber(main: false)
        # Signal thread to finish processing, then wait for it
        @request_queue&.close
        @thread&.join(60)
        # drop references for GC
        @request_queue = nil
        @thread = nil
        # make can_resume? false
        clear_resume_state
      end

      # ===================================================
      # @! Main Fiber API

      # Initialize a new Worker Fiber and Thread, called from the main Fiber
      #
      # The Thread executes ThreadRequest objects from the request_queue and pushes
      # responses to the global response_queue.
      #
      # @param fiber [Fiber] Fiber to process authority block
      # @param authority [Symbol] Authority label
      # @param response_queue [Thread::Queue, nil] Queue for thread responses if enabled
      def initialize(fiber, authority, response_queue)
        raise(ArgumentError, "Fiber and Authority must be provided") unless fiber && authority
        validate_fiber(main: true)

        @fiber = fiber
        @authority = authority
        @response_queue = response_queue
        @fiber.instance_variable_set(:@operation_worker, self)
        if response_queue
          @request_queue = Thread::Queue.new
          @thread = Thread.new do
            Thread.current[:current_authority] = authority
            while (request = @request_queue&.pop)
              @response_queue.push request.execute
            end
          end
        end
        @resume_at = self.class.next_resume_at
        @waiting_for_response = false
        # First resume response is ignored
        @response = true
      end

      # Resume an operation fiber and queue request if there is any from main fiber
      #
      # @return [ThreadRequest, nil] request returned by resume or nil if finished
      def resume
        raise ClosedQueueError unless alive?
        raise NotReadyError, "Cannot resume #{authority} without response!" unless @response
        validate_fiber(main: true)

        request = @fiber.resume(@response)
        # submit the next request for processing
        submit_request(request) if request
        request
      end

      # Shutdown worker called from main fiber
      def shutdown
        validate_fiber(main: true)

        clear_resume_state
        if @fiber&.alive?
          # Trigger fiber to raise an error and thus call deregister
          @fiber.resume(nil)
        end
      end

      # ===================================================
      # @! Worker Fiber API

      # Queue a thread request to be executed from worker fiber
      # otherwise locally if parallel processing is disabled
      #
      # Process flow if parallel enabled:
      # 1. This method:
      #   a. pushes request onto local @request_queue
      #   b. calls Fiber.yield(true) so Scheduler can run other fibers
      # 2. Meanwhile, this fibers thread:
      #   a. pops request off queue
      #   b. processes request
      #   c. pushes response to global response queue
      # 3. Meanwhile, Scheduler on Main fiber:
      #   a. pops response from response queue as they arrive
      #     * calls {#save_thread_response} on associated worker to save each response
      #   c. calls {#resume} on worker when it is its' turn (based on resume_at) and it can_resume (has @response)
      #
      # If parallel processing is not enabled, then the processing occurs in the workers fiber
      #
      # @param request [ThreadRequest] The request to be processed in thread
      def submit_request(request)
        raise NotReadyError, "Cannot make a second request before the first has responded!" if @waiting_for_response
        raise ArgumentError, "Must be passed a valid ThreadRequest! Got: #{request.inspect}" unless request.is_a? ThreadRequest
        validate_fiber(main: false)

        @response = nil
        @waiting_for_response = true
        if @request_queue
          @request_queue&.push request
          response = Fiber.yield true
          raise "Terminated fiber for #{authority} as requested" unless response
        else
          response = save_thread_response request.execute
        end
        response
      end

      private

      def validate_fiber(main: false)
        required_fiber = main ? Constants::MAIN_FIBER : @fiber
        current_id = Fiber.current.object_id
        return if current_id == required_fiber.object_id

        desc = main ? 'main' : 'worker'
        we_are = if current_id == Constants::MAIN_FIBER.object_id
                   'main'
                 elsif current_id == @fiber.object_id
                   'worker'
                 else
                   'other'
                 end
        raise ArgumentError,
              "Must be run within the #{desc} not #{we_are} fiber!"
      end

      # Clear resume state so the operation won't be resumed
      def clear_resume_state
        @resume_at = nil
        @response = nil
        @waiting_for_response = false
      end
    end
  end
end
