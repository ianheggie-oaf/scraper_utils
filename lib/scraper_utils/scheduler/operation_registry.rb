# frozen_string_literal: true

require "fiber"

require_relative "operation_worker"

module ScraperUtils
  module Scheduler
    # Registry of all active OperationWorkers registered to be processed
    class OperationRegistry

      def initialize
        @operations = {}
        @fiber_ids = {}
      end

      def register(fiber, authority)
        authority = authority.to_sym
        operation = OperationWorker.new(fiber, authority, @response_queue)
        @operations[authority] = operation
        @fiber_ids[operation.fiber.object_id] = operation
      end

      # Flag for shutdown and remove from registry
      def deregister(key)
        operation = find(key)
        return unless operation

        operation.close
        # Remove operation from registry since shutdown has done all it can to shut down the thread and fiber
        @operations.delete(operation.authority)
        @fiber_ids.delete(operation.fiber.object_id)
      end

      def current_authority
        find(Fiber.current.object_id)&.authority
      end

      # Find OperationWorker
      # @param key [Integer, String, nil] Fiber's object_id or authority (default current fiber's object_id)
      # @return [OperationWorker, nil] Returns worker or nil if not found
      def find(key = nil)
        key ||= Fiber.current.object_id
        if key.is_a?(Symbol)
          @operations[key]
        elsif key.is_a?(Integer)
          @fiber_ids[key]
        end
      end

      # Removes operations
      def shutdown
        operations.keys.each do |key|
          deregister(key)
        end
      end

      # Returns true if there are no registered operations
      def empty?
        @operations.empty?
      end

      # Returns number of registered operations
      def size
        @operations.size
      end

      # Find operations that can be resumed in resume_at order (may include future resume_at)
      #
      # @return [Array{OperationWorker}] Operations that are alive and have a response to use with resume
      def can_resume
        @operations
          .values
          .select { |op| op.can_resume? }
          .sort_by(&:resume_at)
      end

      # Save the thread response into the thread and mark that it can continue
      def process_thread_response(response)
        operation = find(response.authority)
        operation&.save_thread_response response
      end

      private

      attr_accessor :operations
    end
  end
end
