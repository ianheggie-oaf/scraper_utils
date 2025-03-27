# frozen_string_literal: true

module ScraperUtils
  class DateRangeUtils
    MERGE_ADJACENT_RANGES = true
    PERIODS = [2, 3, 4].freeze

    class << self
      # @return [Integer] Default number of days to cover
      attr_accessor :default_days

      # @return [Integer] Default days to always include in ranges
      attr_accessor :default_everytime

      # @return [Integer, nil] Default max days between any one date being in a range
      attr_accessor :default_max_period

      # Configure default settings for all DateRangeUtils instances
      # @yield [self] Yields self for configuration
      # @example
      #   AgentConfig.configure do |config|
      #     config.default_everytime = 3
      #     config.default_days = 35
      #     config.default_max_period = 5
      #   end
      # @return [void]
      def configure
        yield self if block_given?
      end

      # Reset all configuration options to their default values
      # @return [void]
      def reset_defaults!
        @default_days = ENV.fetch('MORPH_DAYS', 33).to_i # 33
        @default_everytime = ENV.fetch('MORPH_EVERYTIME', 4).to_i # 4
        @default_max_period = ENV.fetch('MORPH_MAX_PERIOD', 2).to_i # 3
      end
    end

    # Set defaults on load
    reset_defaults!

    attr_reader :max_period_used
    attr_reader :extended_max_period

    # Generates one or more date ranges to check the most recent daily through to checking each max_period
    # There is a graduated schedule from the latest `everytime` days through to the oldest of `days` dates which is checked each `max_period` days.
    # @param days [Integer, nil] create ranges that cover the last `days` dates
    # @param everytime [Integer, nil] Always include the latest `everytime` out of `days` dates (minimum 1)
    # @param max_period [Integer, nil] the last `days` dates must be checked at least every `max_period` days (1..4)
    # @param today [Date, nil] overrides the default determination of today at UTC+09:30 (middle of Australia)
    # @return [Array{[Date, Date, String]}] being from_date, to_date and a comment
    #
    # Uses a Fibonacci sequence to create a natural progression of check frequencies.
    # Newer data is checked more frequently, with periods between checks growing
    # according to the Fibonacci sequence (2, 3, 5, 8, 13...) until reaching max_period.
    # This creates an efficient schedule that mimics natural information decay patterns.
    def calculate_date_ranges(days: nil, everytime: nil, max_period: nil, today: nil)
      _calculate_date_ranges(
        Integer(days || self.class.default_days),
        [1, Integer(everytime || self.class.default_everytime)].max,
        Integer(max_period || self.class.default_max_period),
        today || Time.now(in: '+09:30').to_date
      )
    end

    private

    def _calculate_date_ranges(days, everytime, max_period, today)
      @max_period_used = 1
      to_date = today
      valid_periods = PERIODS.select { |p| p <= max_period }
      if !max_period.positive? || !days.positive?
        return []
      elsif valid_periods.empty? || everytime >= days
        # cover everything everytime
        return [[today + 1 - days, today, "everything"]]
      end
      max_period = valid_periods.max
      @max_period_used = max_period

      one_half = ((days - everytime) / 2).to_i
      one_third = ((days - everytime) / 3).to_i
      two_ninths = (2 * (days - everytime) / 9).to_i
      run_ranges =
        case max_period
        when 2
          [
            [[to_date - (one_half + everytime), to_date, "#{max_period}#0+everytime"]],
            [[to_date - days, to_date - (one_half + everytime), "#{max_period}#1"], [to_date - everytime, to_date, "everytime"]]
          ]
        when 3
          [
            [[to_date - days - 1, to_date + two_ninths - days, "3#0"], [to_date - (one_third + everytime), to_date, "2#0+everytime"]],
            [[to_date + two_ninths - days, to_date + 2 * two_ninths - days, "3#1"], [to_date - everytime, to_date, "everytime"]],
            [[to_date + 2 * two_ninths - days, to_date, "3#2+2#0+everytime"]],
            [[to_date - days - 1, to_date + two_ninths - days, "3#3"], [to_date - everytime, to_date, "everytime"]],
            [[to_date + two_ninths - days, to_date + 2 * two_ninths - days, "3#4"], [to_date - (one_third + everytime), to_date, "2#2+everytime"]],
            [[to_date + 2 * two_ninths - days, to_date - (one_third + everytime), "3#5"], [to_date - everytime, to_date, "everytime"]]
          ]
        else
          [
            [[to_date - (one_half + everytime), to_date, "2#0+everytime"]],
            [[to_date - days - 2, to_date - (one_half + everytime), "4#0"], [to_date - everytime, to_date, "everytime"]],
            [[to_date - (one_half + everytime), to_date, "2#1+everytime"]],
            [[to_date - everytime, to_date, "everytime"]]
          ]
        end
      run_number = today.to_date.jd % run_ranges.size

      ranges = run_ranges[run_number]
      if days.positive? && ScraperUtils::DebugUtils.trace?
        LogUtils.log "DEBUG: #{max_period} ranges: #{ranges.inspect}"
      end
      ranges
    end
  end
end
