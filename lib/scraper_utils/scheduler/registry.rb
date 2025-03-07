# frozen_string_literal: true

require "fiber"
require_relative "../er_state"

module ScraperUtils
  module Scheduler
    # Manages the registry of fibers and their associated state
    module Registry
      class << self
        # Core state storage
        def registry
          @registry ||= []
        end

        def fiber_states
          @fiber_states ||= {}
        end

        def exceptions
          @exceptions ||= {}
        end

        # State helpers
        def enabled?
          @enabled ||= false
        end

        def enable!
          reset! unless enabled?
          @enabled = true
        end

        def disable!
          @enabled = false
        end

        # Complete reset of all state
        def reset!
          @registry = []
          @fiber_states = {}
          @exceptions = {}
          @enabled = false
          @delay_requested = 0.0
          @time_slept = 0.0
          @resume_count = 0
          @initial_resume_at = Time.now - 60.0 # one minute ago
        end

        # Fiber and state access
        def current_state
          return nil unless in_fiber?
          fiber_states[Fiber.current.object_id]
        end
        
        def state_for(fiber_id)
          fiber_states[fiber_id]
        end

        def in_fiber?
          !Fiber.current.nil? && registry.include?(Fiber.current)
        end

        def current_authority
          state = current_state
          state&.authority
        end

        # Metrics tracking for reporting
        def delay_metrics
          {
            requested: @delay_requested ||= 0.0,
            slept: @time_slept ||= 0.0,
            resume_count: @resume_count ||= 0
          }
        end

        def update_metrics(type, value)
          case type
          when :delay_requested
            @delay_requested ||= 0.0
            @delay_requested += value
          when :time_slept
            @time_slept ||= 0.0
            @time_slept += value
          when :resume_count
            @resume_count ||= 0
            @resume_count += 1
          end
        end

        # Main operation registration
        def register_operation(authority, &block)
          # Automatically enable fiber scheduling when operations are registered
          enable!

          fiber = Fiber.new do
            begin
              # Execute the block and store the return value
              block.call
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
          @initial_resume_at ||= Time.now - 60.0
          @initial_resume_at += 0.1
          fiber_states[fiber.object_id] = FiberState.new(fiber.object_id, authority)
          fiber_states[fiber.object_id].resume_at = @initial_resume_at
          
          registry << fiber

          if DebugUtils.basic?
            ScraperUtils::Scheduler.log "Registered #{authority} operation with fiber: #{fiber.object_id} for interleaving"
          end
          
          # Process immediately when testing
          fiber.resume if ScraperUtils::RandomizeUtils.sequential?
          fiber
        end
      end
    end
  end
end
