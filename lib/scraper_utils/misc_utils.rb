# frozen_string_literal: true

require_relative "host_throttler"
require_relative "mechanize_utils/agent_config"

module ScraperUtils
  # Misc Standalone Utilities
  module MiscUtils
    THROTTLE_HOSTNAME = "block"

    class << self
      attr_accessor :default_crawl_delay, :default_max_load

      def reset_defaults!
        @default_crawl_delay = MechanizeUtils::AgentConfig.default_crawl_delay
        @default_max_load = MechanizeUtils::AgentConfig.default_max_load
        reset_throttler!
      end

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

      def will_pause_till
        throttler.will_pause_till(THROTTLE_HOSTNAME)
      end

      private

      def throttler
        @throttler ||= HostThrottler.new(
          crawl_delay: default_crawl_delay,
          max_load: default_max_load
        )
      end
    end

    # Initialise defaults after AgentConfig is loaded
    require_relative "mechanize_utils/agent_config"
    reset_defaults!
  end
end
