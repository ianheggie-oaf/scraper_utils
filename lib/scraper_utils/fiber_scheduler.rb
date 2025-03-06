# frozen_string_literal: true

require "fiber"
require_relative "fiber_state"
require_relative "async_command"
require_relative "async_response"
require_relative "thread_scheduler"

module ScraperUtils
  # A utility module for interleaving multiple scraping operations
  # using fibers during connection delay periods. This allows efficient
  # use of wait time by switching between operations.
  module FiberScheduler
    # @return [Array<Fiber>] List of active fibers managed by the scheduler
    def self.registry
      @registry ||= []
    end

    # Centralized storage for fiber state objects
    # @return [Hash<Integer, FiberState>] States for all registered fibers indexed by fiber.object_id
    def self.fiber_states
      @fiber_states ||= {}
    end

    # Get state for a specific fiber
    # @param fiber_id [Integer] The fiber's object_id
    # @return [FiberState, nil] The state for the fiber or nil if not found
    def self.state_for(fiber_id)
      fiber_states[fiber_id]
    end

    # Get current fiber's state
    # @return [FiberState, nil] The state for the current fiber or nil if not in a registered fiber
    def self.current_state
      return nil unless in_fiber?
      state_for(Fiber.current.object_id)
    end

    # Checks if the current code is running within a registered fiber
    #
    # @return [Boolean] true if running in a registered fiber, false otherwise
    def self.in_fiber?
      !Fiber.current.nil? && registry.include?(Fiber.current)
    end

    # Gets the authority associated with the current fiber
    #
    # @return [String, nil] the authority name or nil if not in a fiber
    def self.current_authority
      state = current_state
      state ? state.authority : nil
    end

    # Logs a message, automatically prefixing with authority name if in a fiber
    #
    # @param message [String] the message to log
    # @return [void]
    def self.log(message)
      authority = current_authority
      $stderr.flush
      if authority
        puts "[#{authority}] #{message}"
      else
        puts message
      end
      $stdout.flush
    end

    # Returns a hash of exceptions encountered during processing, indexed by authority
    #
    # @return [Hash{Symbol => Exception}] exceptions by authority
    def self.exceptions
      @exceptions ||= {}
    end

    # Returns a hash of the yielded / block values
    #
    # @return [Hash{Symbol => Any}] values by authority
    def self.values
      @values ||= {}
    end

    # Checks if fiber scheduling is currently enabled
    #
    # @return [Boolean] true if enabled, false otherwise
    def self.enabled?
      @enabled ||= false
    end

    # Enables fiber scheduling
    #
    # @return [void]
    def self.enable!
      reset! unless enabled?
      @enabled = true
    end

    # Disables fiber scheduling
    #
    # @return [void]
    def self.disable!
      @enabled = false
    end

    # Resets the scheduler state, and disables. Use before retrying failed authorities.
    #
    # @return [void]
    def self.reset!
      @registry = []
      @fiber_states = {}
      @exceptions = {}
      @values = {}
      @enabled = false
      @delay_requested = 0.0
      @time_slept = 0.0
      @resume_count = 0
      @initial_resume_at = Time.now - 60.0 # one minute ago
      @thread_scheduler&.shutdown
      @thread_scheduler = nil
    end

    # Gets the thread scheduler instance, creating it if needed
    #
    # @return [ThreadScheduler] the thread scheduler instance
    def self.thread_scheduler
      @thread_scheduler ||= ThreadScheduler.new
    end

    # Queue a network request to be executed by the thread scheduler
    #
    # @param client [Object] the client to use for the request
    # @param method [Symbol] the method to call on the client
    # @param args [Array] the arguments to pass to the method
    # @return [Object] the result of the command
    def self.queue_network_request(client, method, args)
      return nil unless in_fiber?
      
      fiber = Fiber.current
      fiber_id = fiber.object_id
      state = state_for(fiber_id)
      
      # Mark fiber as waiting for response
      state.waiting_for_response = true
      
      # Create and queue the request
      request = NetworkRequest.new(fiber_id, client, method, args)
      thread_scheduler.queue_request(request)
      
      # Log the request if debugging enabled
      if DebugUtils.basic?
        log "Queued #{method} request to thread pool: #{args.first.inspect[0..60]}"
      end
      
      # Yield control back to the scheduler
      Fiber.yield
      
      # When resumed, return the response
      if state.error
        raise state.error
      else
        state.response
      end
    end

    # Delays the current fiber and potentially runs another one
    # Falls back to regular sleep if fiber scheduling is not enabled
    #
    # @param seconds [Numeric] the number of seconds to delay
    # @return [Integer] return from sleep operation or 0
    def self.delay(seconds)
      seconds = 0.0 unless seconds&.positive?
      @delay_requested ||= 0.0
      @delay_requested += seconds

      current_fiber = Fiber.current

      if !enabled? || !current_fiber || registry.size <= 1
        @time_slept ||= 0.0
        @time_slept += seconds
        log("Sleeping #{seconds.round(3)} seconds") if DebugUtils.basic?
        return sleep(seconds)
      end

      now = Time.now
      resume_at = now + seconds
      
      # Set the resume time in the fiber's state
      fiber_id = current_fiber.object_id
      state = state_for(fiber_id)
      state.resume_at = resume_at

      # Don't resume at the same time as someone else,
      # FIFO queue if seconds == 0
      @other_resumes ||= []
      @other_resumes = @other_resumes.delete_if { |t| t < now }
      while @other_resumes.include?(resume_at) && resume_at
        resume_at += 0.01
      end
      
      # Update with adjusted time if needed
      state.resume_at = resume_at if resume_at != now + seconds

      # Yield control back to the scheduler so another fiber can run
      Fiber.yield

      # When we get control back, check if we need to sleep more
      remaining = resume_at - Time.now
      if remaining.positive?
        @time_slept ||= 0.0
        @time_slept += remaining
        log("Sleeping remaining #{remaining.round(3)} seconds") if DebugUtils.basic?
        sleep(remaining)
      end || 0
    end

    # Registers a block to scrape for a specific authority
    #
    # @param authority [String] the name of the authority being processed
    # @yield to the block containing the scraping operation to be run in the fiber
    # @return [Fiber] a fiber that calls the block
    def self.register_operation(authority, &block)
      # Automatically enable fiber scheduling when operations are registered
      enable!

      fiber = Fiber.new do
        begin
          values[authority] = block.call
        rescue StandardError => e
          # Store exception against the authority
          exceptions[authority] = e
        ensure
          # Clean up when done regardless of success/failure
          fiber_states.delete(Fiber.current.object_id)
          registry.delete(Fiber.current)
        end
      end

      # Initialize state for this fiber
      @initial_resume_at += 0.1
      fiber_states[fiber.object_id] = FiberState.new(fiber.object_id, authority)
      fiber_states[fiber.object_id].resume_at = @initial_resume_at
      
      registry << fiber

      if DebugUtils.basic?
        log "Registered #{authority} operation with fiber: #{fiber.object_id} for interleaving"
      end
      
      # Process immediately when testing
      fiber.resume if ScraperUtils::RandomizeUtils.sequential?
      fiber
    end

    # Run all registered fibers until completion
    #
    # @return [Hash] Exceptions that occurred during execution
    def self.run_all
      count = registry.size
      
      # Main scheduling loop
      while registry.any?
        # Check for any completed network requests first
        process_thread_responses
        
        # Find next fiber to run based on time or response readiness
        fiber = find_ready_fiber
        
        if fiber
          if fiber.alive?
            fiber_id = fiber.object_id
            state = state_for(fiber_id)
            
            @resume_count ||= 0
            @resume_count += 1
            
            # Clear response before resuming
            response = state.response
            error = state.error
            state.response = nil
            state.error = nil
            
            # Resume the fiber
            values[state.authority] = fiber.resume
          else
            log "WARNING: fiber is dead but did not remove itself from registry! #{fiber.object_id}"
            registry.delete(fiber)
            fiber_states.delete(fiber.object_id)
          end
        else
          # No fibers ready to run, sleep a short time
          sleep(0.01)
        end
      end

      if @time_slept&.positive? && @delay_requested&.positive?
        percent_slept = (100.0 * @time_slept / @delay_requested).round(1)
      end
      puts
      log "FiberScheduler processed #{@resume_count} calls to delay for #{count} registrations, " \
           "sleeping #{percent_slept}% (#{@time_slept&.round(1)}) of the " \
           "#{@delay_requested&.round(1)} seconds requested."
      puts

      exceptions
    end

    # Process any responses from the thread scheduler
    #
    # @return [Boolean] true if any responses were processed
    def self.process_thread_responses
      return false unless @thread_scheduler
      
      responses = @thread_scheduler.process_responses
      return false if responses.empty?
      
      responses.each do |response|
        state = state_for(response.fiber_id)
        next unless state
        
        # Store the response and error in the fiber's state
        state.response = response.result
        state.error = response.error
        state.waiting_for_response = false
        
        if DebugUtils.basic?
          log "Received response for fiber #{response.fiber_id} in #{response.time_taken.round(3)}s"
        end
      end
      
      true
    end

    # Find a fiber that's ready to run either because it has a response
    # or because its resume time has arrived
    #
    # @return [Fiber, nil] a fiber ready to run or nil if none found
    def self.find_ready_fiber
      now = Time.now
      ready_fiber = nil
      earliest_time = nil
      
      # First check for any fiber with a response
      registry.each do |fiber|
        fiber_id = fiber.object_id
        state = state_for(fiber_id)
        next unless state
        
        if state.response_ready?
          ready_fiber = fiber
          break
        end
        
        # Track earliest scheduled fiber for later use
        resume_time = state.resume_at
        if resume_time && (!earliest_time || resume_time < earliest_time)
          earliest_time = resume_time
          ready_fiber = fiber if now >= resume_time
        end
      end
      
      # If we found a fiber due for execution, log it
      if ready_fiber && DebugUtils.verbose?
        fiber_id = ready_fiber.object_id
        state = state_for(fiber_id)
        
        if state.response_ready?
          log "Resuming fiber #{fiber_id} with response ready"
        elsif state.resume_at
          tardiness = now - state.resume_at
          log "Resuming fiber #{fiber_id} #{tardiness > 0 ? "#{tardiness.round(3)}s late" : "on time"}"
        end
      end
      
      ready_fiber
    end
  end
end
