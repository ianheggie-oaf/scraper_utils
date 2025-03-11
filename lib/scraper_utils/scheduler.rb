# frozen_string_literal: true

require "fiber"

require_relative "scheduler/constants"
require_relative "scheduler/operation_registry"
require_relative "scheduler/operation_worker"

# value objects
require_relative "scheduler/process_request"
require_relative "scheduler/thread_request"

module ScraperUtils
  # A utility module to coordinate the scheduling of work,
  # * interleaving multiple operations (scraping of an authorities site)
  #   uses Fibers (cooperative concurrency) so your code and the libraries you call don't have to be thread safe
  # * Performing mechanize Network I/O in parallel using Threads
  #
  # Process flow
  # 0. operation_workers start with response = ThreadResponse.resume_state = CONTINUE_STATE
  # 1. resumes fiber of operation_worker with the last response when `Time.now` >= resume_at
  # 2. worker fiber
  #    a. sets resume_at based on calculated delay and waiting_for_response
  #    b. pushes request onto local request queue if parallel, otherwise
  #       executes request immediately in fiber and passes response to save_thread_response
  #    c. fiber yields true to main fiber to indicate it wants to continue after resume_at / response arrives
  # 3. one thread for each fiber (if parallel), thread:
  #    a. pops request
  #    b. executes request
  #    c. pushes response onto global response queue (includes response_time)
  # 4. main fiber - schedule_all loop
  #    a. pops any responses and calls save_thread_response on operation_worker
  #    c. resumes(true) operation_worker (fiber) when `Time.now` >= resume_at and not waiting_for_response
  # 5. When worker fiber is finished it returns false to indicate it is finished
  #    OR when shutdown is called resume(false) is called to indicate worker fiber should not continue
  #
  # save_thread_response:
  #    * Updates running average and calculates next_resume_at
  #
  # fiber aborts processing if 2nd argument is true
  # fiber returns nil when finished
  #
  # Workers:
  # * Push process requests onto individual request queues for their thread to process, and yield(true) to scheduler
  #
  # when enough
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
      # Controls if network I/O requests will be processed in parallel using threads
      #
      # @return [Boolean] true if processing network I/O in parallel using threads, otherwise false
      # @note Defaults to true unless the MORPH_DISABLE_THREADS ENV variable is set
      attr_accessor :threaded

      # @return (see #threaded)
      alias threaded? threaded

      # Controls whether Mechanize network requests are executed in parallel using threads
      #
      # @return [Integer] max concurrent workers using fibers and threads, defaults to MAX_WORKERS env variable or 50
      attr_accessor :max_workers

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

      attr_reader :initial_resume_at, :operation_registry, :reset, :response_queue, :totals

    end

    # Returns whether processing of multiple sites is interleaved using fibers
    # @return [Boolean] true if processing is interleaved using fibers, false otherwise
    # @note This value is determined by ScraperUtils::RandomizeUtils.random?
    def self.interleaved?
      max_workers.positive?
    end

    # Resets the scheduler state. Use before retrying failed authorities.
    def self.reset!
      @operation_registry&.shutdown
      @operation_registry = nil
      @response_queue.close if @response_queue
      @threaded = ENV["MORPH_DISABLE_THREADS"].to_s.empty?
      @max_workers = [0, ENV.fetch('MORPH_MAX_WORKERS', Constants::DEFAULT_MAX_WORKERS).to_i].max
      @exceptions = {}
      @totals = Hash.new { 0 }
      @initial_resume_at = Time.now
      @response_queue = Thread::Queue.new if self.threaded?
      @operation_registry = OperationRegistry.new if self.interleaved?
      @reset = true
      @timeout = ENV.fetch('MORPH_TIMEOUT', Constants::DEFAULT_TIMEOUT).to_i
      nil
    end

    # reset on class load
    reset!

    # Registers a block to scrape for a specific authority
    #
    # Block yields(:delay) when operation.resume_at is in the future, and returns :finished when finished
    # @param authority [Symbol] the name of the authority being processed
    # @yield to the block containing the scraping operation to be run in the fiber
    def self.register_operation(authority, &block)
      fiber = Fiber.new do |_, terminate|
        begin
          raise "Terminated fiber for #{authority} before block run" if terminate

          block.call
          # no request
          nil
        rescue StandardError => e
          # Store exception against the authority
          exceptions[authority] = e
          nil
        ensure
          # Clean up when done regardless of success/failure
          operation_registry&.deregister(authority)
        end
      end

      operation = operation_registry&.register(fiber, authority)

      if DebugUtils.basic?
        log "Registered #{authority} operation with fiber: #{fiber.object_id} for interleaving"
      end
      if !interleaved? || operation_registry&.size >= @max_workers
        log "Running batch of #{operation_registry&.size} operations immediately"
        run_operations
      end
      # return operation for ease of testing
      operation
    end

    # Run all registered operations until completion
    #
    # @return [Hash] Exceptions that occurred during execution
    def self.run_operations
      Timeout.timeout(timeout) do
        count = operation_registry&.size

        # Main scheduling loop - process till there is nothing left to do
        until @operation_registry.empty?
          # Save results from threads in operation state so more operation fibers can be resumed
          while (thread_response = get_response)
            @operation_registry.save_thread_response(thread_response)
          end

          delay = Constants::POLL_PERIOD
          # Find the operation that ready to run with the earliest resume_at
          operation = @operation_registry.can_resume.first

          if !operation
            # No fibers ready to run, sleep a short time
            sleep(delay)
            @totals[:poll_sleep] += delay
          elsif !operation.alive?
            log "WARNING: removing dead operation for #{operation.authority} - it should have cleaned up after itself!"
            operations.delete(operation.authority)
          else
            # Sleep till operation should be resumed, but no longer than POLL_PERIOD
            # as responses may come in soon that enable an earlier operation to be resumed
            delay = [(operation.resume_at - Time.now).to_f, delay].min
            unless delay.positive?
              @totals[:resume_count] += 1
              # resume fiber with response to last request
              operation.resume
            end
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

    # ===========================================================
    # @!group Fiber Api

    # Execute Mechanize network request [usually] from within a fiber
    #
    # @param client [MechanizeClient] client to be used to process request
    # @param method_name [Symbol] method to be called on client
    # @param args [Array] Arguments to be used with method call
    # @return [Object] response from method call on client
    def self.execute_request(client, method_name, args)
      authority = current_authority
      # execute immediately if not in a worker fiber
      return client.send(method_name, args) unless authority

      request = Scheduler::ProcessRequest.new(authority, client, method_name, args)
      if DebugUtils.basic?
        log "Calling Fiber.yield #{request.inspect}"
      end
      response = Fiber.yield true
      unless response.is_a?(ThreadResponse)
        raise "Expected ThreadResponse, got: #{response.inspect}"
      end
      response.result!
    end

    # Records

    # Gets the authority associated with the current fiber or thread
    #
    # @return [Symbol, nil] the authority name or nil if not in a fiber
    def self.current_authority
      @operation_registry&.current_authority
    end

    private

    # Return the next response, returns nil if queue is empty
    #
    # @return [ThreadResponse, nil] Result of request execution
    def self.get_response(non_block = true)
      return nil if non_block && @response_queue.empty?

      @response_queue.pop(non_block)
    end

    def self.report_summary(count)
      percent_polling = 0
      if @totals[:delay_requested].positive?
        percent_polling = (100.0 * @totals[:poll_sleep] / @totals[:delay_requested]).round(1)
      end
      puts
      LogUtils.log "FiberScheduler processed #{@totals[:resume_count]} calls for #{count} registrations, " \
                     "waiting #{percent_polling}% (#{@totals[:poll_sleep]&.round(1)}) of the " \
                     "#{@totals[:delay_requested]&.round(1)} seconds requested."
      puts
    end
  end
end
