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
  # 0. operation_workers start with response = true as the first resume passes args to block and response is ignored
  # 1. resumes fiber of operation_worker with the last response when `Time.now` >= resume_at
  # 2. worker fiber calls {Scheduler.execute_request}
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
    # These Methods should only be called from main (initial) fiber

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
      # @return [Integer] max concurrent workers using fibers and threads, defaults to MORPH_MAX_WORKERS env variable or 50
      attr_accessor :max_workers

      # @return [Hash{Symbol => Exception}] exceptions by authority
      attr_reader :exceptions

      # Returns the run_operations timeout
      # On timeout a message will be output and the ruby program will exit with exit code 124.
      #
      # @return [Integer] Overall process timeout in seconds (default MORPH_RUN_TIMEOUT ENV value or 6 hours)
      attr_accessor :run_timeout

      # Private accessors for internal use

      private

      attr_reader :initial_resume_at, :operation_registry, :reset, :response_queue, :totals

    end

    # Resets the scheduler state. Use before retrying failed authorities.
    def self.reset!
      @operation_registry&.shutdown
      @operation_registry = nil
      @response_queue.close if @response_queue
      @threaded = ENV["MORPH_DISABLE_THREADS"].to_s.empty?
      @max_workers = [1, ENV.fetch('MORPH_MAX_WORKERS', Constants::DEFAULT_MAX_WORKERS).to_i].max
      @exceptions = {}
      @totals = Hash.new { 0 }
      @initial_resume_at = Time.now
      @response_queue = Thread::Queue.new if self.threaded?
      @operation_registry = OperationRegistry.new
      @reset = true
      @run_timeout = ENV.fetch('MORPH_RUN_TIMEOUT', Constants::DEFAULT_TIMEOUT).to_i
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
      fiber = Fiber.new do |continue|
        begin
          raise "Terminated fiber for #{authority} before block run" unless continue

          block.call
        rescue StandardError => e
          # Store exception against the authority
          exceptions[authority] = e
        ensure
          # Clean up when done regardless of success/failure
          operation_registry&.deregister
        end
        # no further requests
        nil
      end

      operation = operation_registry&.register(fiber, authority)

      if DebugUtils.basic?
        LogUtils.log "Registered #{authority} operation with fiber: #{fiber.object_id} for interleaving"
      end
      if operation_registry&.size >= @max_workers
        LogUtils.log "Running batch of #{operation_registry&.size} operations immediately"
        run_operations
      end
      # return operation for ease of testing
      operation
    end

    # Run all registered operations until completion
    #
    # @return [Hash] Exceptions that occurred during execution
    def self.run_operations
      monitor_run_time = Thread.new do
        sleep run_timeout
        desc = "#{(run_timeout / 3600.0).round(1)} hours"
        desc = "#{(run_timeout / 60.0).round(1)} minutes" if run_timeout < 100 * 60
        desc = "#{run_timeout} seconds" if run_timeout < 100
        LogUtils.log "ERROR: Script exceeded maximum allowed runtime of #{desc}!\n" \
                       "Forcibly terminating process!"
        Process.exit!(124)
      end
      count = operation_registry&.size

      # Main scheduling loop - process till there is nothing left to do
      until @operation_registry.empty?
        save_thread_responses
        resume_next_operation
      end

      report_summary(count)

      exceptions
    ensure
      # Kill the monitoring thread if we finish normally
      monitor_run_time.kill if monitor_run_time.alive?
      monitor_run_time.join(2)
    end

    # ===========================================================
    # @!group Fiber Api
    # These Methods should be called from the worker's own fiber but can be called from the main fiber

    # Execute Mechanize network request in parallel using the fiber's thread
    # This allows multiple network I/O requests to be waiting for a response in parallel
    # whilst responses that have arrived can be processed by their fibers.
    #
    # @example Replace this code in your scraper
    #   page = agent.get(url_period(url, period, webguest))
    #
    # @example With this code
    #   page = ScraperUtils::Scheduler.execute_request(agent, :get, [url_period(url, period, webguest)])
    #
    # @param client [MechanizeClient] client to be used to process request
    # @param method_name [Symbol] method to be called on client
    # @param args [Array] Arguments to be used with method call
    # @return [Object] response from method call on client
    def self.execute_request(client, method_name, args)
      operation = current_operation
      # execute immediately if not in a worker fiber
      return client.send(method_name, args) unless operation

      request = Scheduler::ProcessRequest.new(operation.authority, client, method_name, args)
      log "Submitting request #{request.inspect}" if DebugUtils.basic?
      response = operation.submit_request(request)
      unless response.is_a?(ThreadResponse)
        raise "Expected ThreadResponse, got: #{response.inspect}"
      end
      response.result!
    end

    # Gets the authority associated with the current fiber or thread
    #
    # @return [Symbol, nil] the authority name or nil if not in a fiber
    def self.current_authority
      current_operation&.authority
    end

    # @!endgroup
    # ===========================================================

    private

    # Save results from threads in operation state so more operation fibers can be resumed
    def self.save_thread_responses
      while (thread_response = get_response)
        operation = @operation_registry&.find(thread_response.authority)
        operation&.save_thread_response(thread_response)
        LogUtils.log "WARNING: orphaned thread response ignored: #{thread_response.inspect}", thread_response.authority
      end
    end

    # Resume next operation or sleep POLL_PERIOD if non are ready
    def self.resume_next_operation
      delay = Constants::POLL_PERIOD
      # Find the operation that ready to run with the earliest resume_at
      can_resume_operations = @operation_registry&.can_resume
      operation = can_resume_operations&.first

      if !operation
        # All the fibers must be waiting for responses, so sleep a bit to allow the responses to arrive
        @operation_registry&.cleanup_zombies
        sleep(delay)
        @totals[:wait_response] += delay
      else
        delay = [(operation.resume_at - Time.now).to_f, delay].min
        if delay.positive?
          # Wait a bit for a fiber to be ready to run
          sleep(delay)
          waiting_for_delay = delay * can_resume_operations&.size.to_f / (@operation_registry&.size || 1)
          @totals[:wait_delay] += waiting_for_delay
          @totals[:wait_response] += delay - waiting_for_delay
        else
          @totals[:resume_count] += 1
          # resume fiber with response to last request that is ready to be resumed now
          operation.resume
        end
        operation
      end
    end

    # Return the next response, returns nil if queue is empty
    #
    # @return [ThreadResponse, nil] Result of request execution
    def self.get_response(non_block = true)
      return nil if @response_queue.nil? || (non_block && @response_queue.empty?)

      @response_queue.pop(non_block)
    end

    def self.current_operation
      @operation_registry&.find
    end

    def self.report_summary(count)
      wait_delay_percent = 0
      wait_response_percent = 0
      delay_requested = [@totals[:wait_delay], @totals[:wait_response]].sum
      if delay_requested.positive?
        wait_delay_percent = (100.0 * @totals[:wait_delay] / delay_requested).round(1)
        wait_response_percent = (100.0 * @totals[:wait_response] / delay_requested).round(1)
      end
      puts
      LogUtils.log "Scheduler processed #{@totals[:resume_count]} calls for #{count} registrations, " \
                     "with #{wait_delay_percent}% of #{delay_requested.round(1)} seconds spent keeping under max_load, " \
                     "and #{wait_response_percent}% waiting for network I/O requests."
      puts
    end
  end
end
