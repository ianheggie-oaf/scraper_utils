# frozen_string_literal: true

module ScraperUtils
  # Misc Standalone Utilities
  module MiscUtils
    MAX_PAUSE = 120.0

    class << self
      attr_accessor :pause_duration

      # Throttle block to be nice to servers we are scraping
      def throttle_block(extra_delay: 0.5)
        if @pause_duration&.positive?
          puts "Pausing #{@pause_duration}s" if ScraperUtils::DebugUtils.trace?
          sleep(@pause_duration)
        end
        start_time = Time.now.to_f
        result = yield
        @pause_duration = (Time.now.to_f - start_time + extra_delay).round(3).clamp(0.0, MAX_PAUSE)
        result
      end
    end
  end
end
