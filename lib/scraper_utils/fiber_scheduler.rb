# frozen_string_literal: true

require "fiber"

module ScraperUtils
  # A utility module for interleaving multiple scraping operations
  # using fibers during connection delay periods. This allows efficient
  # use of wait time by switching between operations.
  module FiberScheduler
    # @return [Array<Fiber>] List of active fibers managed by the scheduler
    def self.registry
      @registry ||= []
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
      return nil unless in_fiber?

      Fiber.current.instance_variable_get(:@authority)
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
      @exceptions = {}
      @values = {}
      @enabled = false
      @delay_requested = 0.0
      @time_slept = 0.0
      @resume_count = 0
      @initial_resume_at = Time.now - 60.0 # one minute ago
    end

    # Registers a block to scrape for a specific authority
    #
    # @param authority [String] the name of the authority being processed
    # @yield to the block containing the scraping operation to be run in the fiber
    # @return [Fiber] a fiber that calls the block. With @authority and @resume_at instance vars
    def self.register_operation(authority, &block)
      # Automatically enable fiber scheduling when operations are registered
      enable!

      fiber = Fiber.new do
        values[authority] = block.call
      rescue StandardError => e
        # Store exception against the authority
        exceptions[authority] = e
      ensure
        # Remove itself when done regardless of success/failure
        registry.delete(Fiber.current)
      end

      # Start fibres in registration order
      @initial_resume_at += 0.1
      fiber.instance_variable_set(:@resume_at, @initial_resume_at)
      fiber.instance_variable_set(:@authority, authority)
      registry << fiber

      if DebugUtils.basic?
        FiberScheduler.log "Registered #{authority} operation with fiber: #{fiber.object_id} for interleaving"
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
      while (fiber = find_earliest_fiber)
        if fiber.alive?
          authority = begin
            fiber.instance_variable_get(:@authority)
          rescue StandardError
            nil
          end
          @resume_count ||= 0
          @resume_count += 1
          values[authority] = fiber.resume
        else
          FiberScheduler.log "WARNING: fiber is dead but did not remove itself from registry! #{fiber.object_id}"
          registry.delete(fiber)
        end
      end

      if @time_slept&.positive? && @delay_requested&.positive?
        percent_slept = (100.0 * @time_slept / @delay_requested).round(1)
      end
      puts
      FiberScheduler.log "FiberScheduler processed #{@resume_count} calls to delay for #{count} registrations, " \
           "sleeping #{percent_slept}% (#{@time_slept&.round(1)}) of the " \
           "#{@delay_requested&.round(1)} seconds requested."
      puts

      exceptions
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

      # Don't resume at the same time as someone else,
      # FIFO queue if seconds == 0
      @other_resumes ||= []
      @other_resumes = @other_resumes.delete_if { |t| t < now }
      while @other_resumes.include?(resume_at) && resume_at
        resume_at += 0.01
      end

      # Used to compare when other fibers need to be resumed
      current_fiber.instance_variable_set(:@resume_at, resume_at)

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

    # Finds the fiber with the earliest wake-up time
    #
    # @return [Fiber, nil] the fiber with the earliest wake-up time or nil if none found
    def self.find_earliest_fiber
      earliest_time = nil
      earliest_fiber = nil

      registry.each do |fiber|
        resume_at = fiber.instance_variable_get(:@resume_at)
        if earliest_time.nil? || resume_at < earliest_time
          earliest_time = resume_at
          earliest_fiber = fiber
        end
      end

      earliest_fiber
    end

    # Mark methods as private
    private_class_method :find_earliest_fiber
  end
end
