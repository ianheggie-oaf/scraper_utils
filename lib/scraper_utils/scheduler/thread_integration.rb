# frozen_string_literal: true

require "fiber"
require_relative "../nc_command"
require_relative "../nc_response"
require_relative "../ead_scheduler"
require_relative "registry"

module ScraperUtils
  module Scheduler
    # Handles integration with ThreadScheduler for parallel execution
    module ThreadIntegration
      class << self
        # Access to the thread scheduler instance
        def thread_scheduler
          @thread_scheduler ||= ThreadScheduler.new
        end

        # Reset the thread scheduler reference
        def reset_thread_scheduler
          @thread_scheduler&.shutdown
          @thread_scheduler = nil
        end

        # Queue an async command to be executed by the thread scheduler
        #
        # @param client [Object] the object to call the method on
        # @param method [Symbol] the method to call on the client
        # @param args [Array] the arguments to pass to the method
        # @return [Object] the result of the command when it completes
        def queue_async_command(client, method, args)
          raise "Cannot queue async command outside of a registered fiber" unless Registry.in_fiber?
          
          fiber = Fiber.current
          fiber_id = fiber.object_id
          state = Registry.state_for(fiber_id)

          unless state.waiting_for_response?
            raise "Cannot queue second async command before getting response from first on fiber"
          end
          
          # Mark fiber as waiting for response
          state.waiting_for_response = true
          
          # Create and queue the command
          command = AsyncCommand.new(fiber_id, client, method, args)
          thread_scheduler.queue_request(command)
          
          # Log the request if debugging enabled
          if DebugUtils.basic?
            ScraperUtils::Scheduler.log "Queued #{method} async command to thread pool: #{args.first.inspect[0..60]}"
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
      end
    end
  end
end
