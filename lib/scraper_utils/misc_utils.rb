# frozen_string_literal: true

require_relative "host_throttler"

module ScraperUtils
  # Misc Standalone Utilities
  module MiscUtils
    THROTTLE_HOSTNAME = "block"

    class << self
      # Throttle block to be nice to servers we are scraping.
      # Time spent inside the block (parsing, saving) counts toward the delay.
      def throttle_block
        throttler.before_request(THROTTLE_HOSTNAME)
        begin
          result = yield
          throttler.after_request(THROTTLE_HOSTNAME)
          result
        rescue StandardError => e
          throttler.after_request(THROTTLE_HOSTNAME, overloaded: HostThrottler.overload_error?(e))
          raise
        end
      end

      # Reset the internal throttler (useful in tests)
      def reset_throttler!
        @throttler = nil
      end

      private

      def throttler
        @throttler ||= HostThrottler.new
      end
    end
  end
end
