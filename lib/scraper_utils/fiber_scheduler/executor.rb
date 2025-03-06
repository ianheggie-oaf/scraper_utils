# frozen_string_literal: true

require "fiber"
require_relative "registry"
require_relative "thread_integration"

module ScraperUtils
  module FiberScheduler
    # Handles execution and scheduling of fibers
    module Executor
      class << self
        # Delays the current fiber and potentially runs another one
        def delay(seconds)
          seconds = 0.0 unless seconds&.positive?
          Registry.update_metrics(:delay_requested, seconds)

          current_fiber = Fiber.current

          # Fall back to plain sleep if scheduling not possible
          if !Registry.enabled? || !current_fiber || Registry.registry.size <= 1
            Registry.update_metrics(:time_slept, seconds)
            ScraperUtils::FiberScheduler.log("Sleeping #{seconds.round(3)} seconds") if DebugUtils.basic?
            return sleep(seconds)
          end

          now = Time.now
          resume_at = now + seconds
          
          # Set the resume time in the fiber's state
          fiber_id = current_fiber.object_id
          state = Registry.state_for(fiber_id)
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
            Registry.update_metrics(:time_slept, remaining)
            ScraperUtils::FiberScheduler.log("Sleeping remaining #{remaining.round(3)} seconds") if DebugUtils.basic?
            sleep(remaining)
          end || 0
        end

        # Run all registered fibers until completion
        def run_all
          count = Registry.registry.size
          
          # Main scheduling loop
          while Registry.registry.any?
            # Check for any completed async commands first
            process_thread_responses
            
            # Find next fiber to run based on time or response readiness
            fiber = find_ready_fiber
            
            if fiber
              if fiber.alive?
                fiber_id = fiber.object_id
                state = Registry.state_for(fiber_id)
                
                Registry.update_metrics(:resume_count, 1)
                
                # Clear response before resuming
                response = state.response
                error = state.error
                state.response = nil
                state.error = nil
                
                # Resume the fiber and store its return value
                # We save the return value but don't use it directly
                fiber.resume
              else
                ScraperUtils::FiberScheduler.log "WARNING: fiber is dead but did not remove itself from registry! #{fiber.object_id}"
                Registry.registry.delete(fiber)
                Registry.fiber_states.delete(fiber.object_id)
              end
            else
              # No fibers ready to run, sleep a short time
              sleep(0.01)
            end
          end

          # Log results
          metrics = Registry.delay_metrics
          
          if metrics[:slept] > 0 && metrics[:requested] > 0
            percent_slept = (100.0 * metrics[:slept] / metrics[:requested]).round(1)
          end
          
          puts
          ScraperUtils::FiberScheduler.log "FiberScheduler processed #{metrics[:resume_count]} calls to delay for #{count} registrations, " \
              "sleeping #{percent_slept}% (#{metrics[:slept].round(1)}) of the " \
              "#{metrics[:requested].round(1)} seconds requested."
          puts

          Registry.exceptions
        end

        # Process any responses from the thread scheduler
        def process_thread_responses
          thread_scheduler = ThreadIntegration.thread_scheduler
          return false unless thread_scheduler
          
          responses = thread_scheduler.process_responses
          return false if responses.empty?
          
          responses.each do |response|
            state = Registry.state_for(response.external_id)
            next unless state
            
            # Store the response and error in the fiber's state
            state.response = response.result
            state.error = response.error
            state.waiting_for_response = false
            
            if DebugUtils.basic?
              ScraperUtils::FiberScheduler.log "Received response for fiber #{response.external_id} in #{response.time_taken.round(3)}s"
            end
          end
          
          true
        end

        # Find a fiber that's ready to run either because it has a response
        # or because its resume time has arrived
        def find_ready_fiber
          now = Time.now
          ready_fiber = nil
          earliest_time = nil
          
          # First check for any fiber with a response
          Registry.registry.each do |fiber|
            fiber_id = fiber.object_id
            state = Registry.state_for(fiber_id)
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
            state = Registry.state_for(fiber_id)
            
            if state.response_ready?
              ScraperUtils::FiberScheduler.log "Resuming fiber #{fiber_id} with response ready"
            elsif state.resume_at
              tardiness = now - state.resume_at
              ScraperUtils::FiberScheduler.log "Resuming fiber #{fiber_id} #{tardiness > 0 ? "#{tardiness.round(3)}s late" : "on time"}"
            end
          end
          
          ready_fiber
        end
      end
    end
  end
end
