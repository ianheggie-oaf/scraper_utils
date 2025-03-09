# frozen_string_literal: true

require "fiber"

require_relative "scheduler/fiber_registry"

# require_relative "scheduler/thread_integration"
require_relative "scheduler/thread_pool"

# value objects
require_relative "scheduler/fiber_operation"
require_relative "scheduler/delay_request"
require_relative "scheduler/process_request"
require_relative "scheduler/thread_request"
require_relative "scheduler/thread_response"

module ScraperUtils
  # A utility module to coordinate the scheduling of work,
  # * interleaving multiple operations (scraping of an authorities site)
  #   uses Fibers (cooperative concurrency) so your code and the libraries you call don't have to be thread safe
  # * Performing mechanize Network I/O in parallel using Threads
  #
  # Thread safe Implementation:
  # * Uses fibers for each authority with its own mechanize agent so operations don't need to be thread safe
  # * Only Mechanize requests are run in threads in parallel whilst they wait for network response
  # * Uses message passing (using Queue's) to avoid having to share state between threads.
  # * Execute request does not return till the response has been received from the thread,
  #   so the fiber's mechanize agent that is shared with the thread isn't used in multiple threads at once
  # * Only one execute request per authority fiber can be in the thread request queue at any one time
  module Scheduler
    # @!group Main fiber / thread Api
    class << self
      # Controls whether Mechanize network requests are executed in parallel using threads
      #
      # @return [Boolean] true if network requests are executed in parallel using threads, false otherwise
      # @note Defaults to true unless the MORPH_NOT_PARALLEL or MORPH_PROCESS_SEQUENTIALLY ENV variables are set
      attr_accessor :parallel

      # Reports if Mechanize network requests are executed in parallel using threads
      # 
      # @return (see #parallel)
      alias parallel? parallel

      # @return [Hash{Symbol => Exception}] exceptions by authority
      attr_reader :exceptions

      # Returns the run_operations timeout
      # On timeout a message will be output
      # The ruby process with exit with status 124 on timeout unless timeout <= 3600
      #
      # @return [Integer] Overall process timeout in seconds (default MORPH_TIMEOUT ENV value or 6 hours)
      attr_accessor :timeout

      # Private accessors for internal use

      private

      attr_reader :fiber_registry, :thread_pool, :delay_requested,
                  :poll_sleep, :resume_count, :initial_resume_at, :reset
    end

    # Returns whether processing of multiple sites is interleaved using fibers
    # @return [Boolean] true if processing is interleaved using fibers, false otherwise
    # @note This value is determined by ScraperUtils::RandomizeUtils.random?
    def self.interleaved?
      ScraperUtils::RandomizeUtils.random?
    end

    # Resets the scheduler state. Use before retrying failed authorities.
    def self.reset!
      @fiber_registry&.shutdown
      @thread_pool&.shutdown
      @parallel = ENV['MORPH_NOT_PARALLEL'].to_s.empty? && self.interleaved?
      @exceptions = {}
      @delay_requested = 0.0
      @poll_sleep = 0.0
      @resume_count = 0
      @initial_resume_at = Time.now
      @fiber_registry = FiberRegistry.new if self.interleaved?
      @thread_pool = ThreadPool.new if self.parallel?
      @reset = true
      @timeout = ENV.fetch('MORPH_TIMEOUT', 6 * 60 * 60).to_i
      nil
    end

    # reset on class load
    reset!

    # Registers a block to scrape for a specific authority
    #
    # @param authority [Symbol] the name of the authority being processed
    # @yield to the block containing the scraping operation to be run in the fiber
    def self.register_operation(authority, &block)
      fiber = Fiber.new do
        begin
          block.call
        rescue StandardError => e
          # Store exception against the authority
          exceptions[authority] = e
        ensure
          # Clean up when done regardless of success/failure
          fiber_registry.deregister(authority)
        end
      end

      operation = fiber_registry.register(fiber, authority)

      if DebugUtils.basic?
        log "Registered #{authority} operation with fiber: #{fiber.object_id} for interleaving"
      end
      unless interleaved?
        log "Running #{authority} operation immediately as interleaving is disabled"
        run_operations
      end
      # return operation for ease of testing
      operation
    end

    POLL_PERIOD = 0.01

    # Run all registered operations until completion
    #
    # @return [Hash] Exceptions that occurred during execution
    def self.run_operations
      Timeout.timeout(timeout) do
        count = fiber_registry.size

        # Main scheduling loop
        until @fiber_registry.empty?
          while (thread_response = @thread_pool.get_response)
            process_thread_response(thread_response)
          end
          # Just in case somehow a dead operation occurs
          @fiber_registry.remove_dead_operations
          # Find the operation that ready to run with the earliest resume_at
          operation = @fiber_registry.ready_to_run.first

          if operation&.alive?
            @resume_count ||= 0
            @resume_count += 1

            # Resume the fiber with the results of the last request
            operation.resume
          elsif operation
            log "WARNING: operation is dead but did not remove itself from fiber_registry! #{operation.inspect}"
            operations.delete(operation.object_id)
          else
            # No fibers ready to run, sleep a short time
            sleep(POLL_PERIOD)
            @poll_sleep += POLL_PERIOD
          end
        end

        report_summary(count)

        exceptions
      end
    rescue Timeout::Error
      STDERR.puts "ERROR: Script exceeded maximum allowed runtime of #{(timeout / 3600.0).round(2)} hours!"
      STDERR.puts "SQLite operations may have stalled. Forcibly terminating process..."
      Process.exit!(124) if timeout >= 3600
      exceptions
    end

    # @!group Fiber Api

    # Execute Mechanize network request [usually] from within a fiber
    #
    # @param client [MechanizeClient] client to be used to process request
    # @param method_name [Symbol] method to be called on client
    # @param args [Array] Arguments to be used with method call
    # @return [Object] response from method call on client
    def self.execute_request(client, method_name, args)
      authority = current_authority
      return client.send(method_name, args) unless authority && @thread_pool

      request = Scheduler::ProcessRequest.new(authority, client, method_name, args)
      if DebugUtils.basic?
        log "Calling Fiber.yield :process, #{request.inspect}"
      end
      response = Fiber.yield :process, request
      unless response.is_a?(ThreadResponse) && response.response_type == :processed
        raise "Expected ThreadResponse.response_type == :processed, got: #{response.inspect}"
      end
      response.result!
    end

    # Delays the current fiber and potentially runs another one
    # Falls back to regular sleep if fiber scheduling is not enabled, or we are not the main Thread
    #
    # @param seconds [Numeric] the number of seconds to delay
    # @return [Integer] return from sleep operation or 0
    def self.delay(seconds)
      authority = current_authority
      return sleep(seconds) unless authority || Thread.current != Thread.main

      delay_till = Time.now + seconds
      request = Scheduler::DelayRequest.new(authority, delay_till)
      if DebugUtils.basic?
        log "Calling Fiber.yield :delay, #{request.inspect}"
      end
      response = Fiber.yield :delay, request
      unless response.is_a?(ThreadResponse) && response.response_type == :delayed
        raise "Expected ThreadResponse.response_type == :delayed, got: #{response.inspect}"
      end
      response.result!
    end

    # Gets the authority associated with the current fiber
    #
    # @return [Symbol, nil] the authority name or nil if not in a fiber
    def self.current_authority
      @fiber_registry&.current_authority || @thread_pool&.current_authority
    end

    # @!group Internal Methods

    def self.process_thread_response(thread_response)
      @thread_pool.process_thread_response(thread_response)
    end

    private

    def self.report_summary(count)
      percent_polling = 0
      if @poll_sleep&.positive? && @delay_requested&.positive?
        percent_polling = (100.0 * @poll_sleep / @delay_requested).round(1)
      end
      puts
      LogUtils.log "FiberScheduler processed #{@resume_count} calls for #{count} registrations, " \
                     "waiting #{percent_polling}% (#{@poll_sleep&.round(1)}) of the " \
                     "#{@delay_requested&.round(1)} seconds requested."
      puts
    end
  end
end
