# frozen_string_literal: true

module ScraperUtils
  # Tracks per-host next-allowed-request time so that time spent parsing
  # and saving records counts toward the crawl delay rather than being
  # added on top of it.
  #
  # Usage:
  #   throttler = HostThrottler.new(crawl_delay: 1.0, max_load: 50.0)
  #   throttler.before_request(hostname)   # sleep until ready
  #   # ... make request ...
  #   throttler.after_request(hostname)    # record timing, schedule next slot
  #   throttler.after_request(hostname, overloaded: true)  # double delay + 5s
  class HostThrottler
    MAX_DELAY = 120.0

    # @param crawl_delay [Float] minimum seconds between requests per host
    # @param max_load [Float] target server load percentage (10..100);
    #   50 means response_time == pause_time
    def initialize(crawl_delay: 0.0, max_load: nil)
      @crawl_delay = crawl_delay.to_f
      # Clamp between 10 (delay 9x response) and 100 (no extra delay)
      @max_load = max_load ? max_load.to_f.clamp(10.0, 100.0) : nil
      @next_request_at = {}   # hostname => Time
      @request_started_at = {} # hostname => Time
    end

    # Sleep until this host's throttle window has elapsed.
    # Records when the request actually started.
    # @param hostname [String]
    # @return [void]
    def before_request(hostname)
      target = @next_request_at[hostname]
      if target
        remaining = target - Time.now
        sleep(remaining) if remaining > 0
      end
      @request_started_at[hostname] = Time.now
    end

    # Calculate and store the next allowed request time for this host.
    # @param hostname [String]
    # @param overloaded [Boolean] true when the server signalled overload
    #   (HTTP 429/500/503); doubles the normal delay and adds 5 seconds.
    # @return [void]
    def after_request(hostname, overloaded: false)
      started = @request_started_at[hostname] || Time.now
      response_time = Time.now - started

      delay = @crawl_delay
      if @max_load
        delay += (100.0 - @max_load) * response_time / @max_load
      end

      if overloaded
        delay = delay + response_time * 2 + 5.0
      end

      delay = delay.round(3).clamp(0.0, MAX_DELAY)
      @next_request_at[hostname] = Time.now + delay

      if DebugUtils.basic?
        msg = "HostThrottler: #{hostname} response=#{response_time.round(3)}s"
        msg += " OVERLOADED" if overloaded
        msg += ", Will delay #{delay}s before next request"
        LogUtils.log(msg)
      end
    end

    # Duck-type check for HTTP overload errors across Mechanize, HTTParty, etc.
    # @param error [Exception]
    # @return [Boolean]
    def self.overload_error?(error)
      code = if error.respond_to?(:response) && error.response.respond_to?(:code)
               error.response.code.to_i          # HTTParty style
             elsif error.respond_to?(:response_code)
               error.response_code.to_i          # Mechanize style
             end
      [429, 500, 503].include?(code)
    end
  end
end
