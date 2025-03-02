# frozen_string_literal: true

module ScraperUtils
  class DateRangeUtils
    MERGE_ADJACENT_RANGES = true
    PERIODS = [2, 3, 5, 8].freeze

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
        @default_max_period = ENV.fetch('MORPH_MAX_PERIOD', 3).to_i # 3
      end
    end

    # Set defaults on load
    reset_defaults!

    attr_reader :max_period_used
    attr_reader :extended_max_period

    # Generates one or more date ranges to check the most recent daily through to checking each max_period
    # There is a graduated schedule from the latest `everytime` days through to the oldest of `days` dates which is checked each `max_period` days.
    # @param days [Integer, nil] create ranges that cover the last `days` dates
    # @param everytime [Integer, nil] Always include the latest `everytime` out of `days` dates
    # @param max_period [Integer, nil] the last `days` dates must be checked at least every `max_period` days
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
        Integer(everytime || self.class.default_everytime),
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

      run_number = today.to_date.jd
      ranges = []
      if everytime.positive?
        ranges << [to_date + 1 - everytime, to_date, "everytime"]
        days -= everytime
        to_date -= everytime
      end

      periods = valid_periods.dup
      loop do
        period = periods.shift
        break if period.nil? || period >= max_period || !days.positive?

        # puts "DEBUG: #{period} day periods started #{(today - to_date).to_i} days in."
        period.times do |index|
          break unless days.positive?

          this_period = [days, period].min
          break if this_period <= 0

          earliest_from = to_date - days
          # we are working from the oldest back towards today
          if run_number % period == index
            from = to_date - index - (this_period - 1)
            from = earliest_from if from < earliest_from
            to = [today, to_date - index].min
            break if from > to

            @max_period_used = [this_period, @max_period_used].max
            if ranges.any? && ranges.last[0] <= to + 1 && MERGE_ADJACENT_RANGES
              # extend adjacent range
              ranges.last[0] = [from, ranges.last[0]].min
              ranges.last[2] = "#{period}\##{index},#{ranges.last[2]}"
            else
              to = ranges.last[0] - 1 if ranges.any? && to >= ranges.last[0]
              ranges << [from, to, "#{period}\##{index}"]
            end
          end
          days -= this_period
          to_date -= this_period
        end
      end
      # remainder of range at max_period, whatever that is
      # puts "DEBUG: #{max_period} day periods started #{(today - to_date).to_i} days in." if days.positive?
      index = -1
      while days.positive?
        index += 1
        this_period = [days, max_period].min
        break if this_period <= 0

        earliest_from = to_date - days
        if (run_number % max_period) == (index % max_period)
          from = to_date - index - (this_period - 1)
          from = earliest_from if from < earliest_from
          to = to_date - index
          break if from > to

          @max_period_used = [this_period, @max_period_used].max
          if ranges.any? && ranges.last[0] <= to + 1 && MERGE_ADJACENT_RANGES
            # extend adjacent range
            ranges.last[0] = [from, ranges.last[0]].min
            ranges.last[2] = "#{this_period}\##{index},#{ranges.last[2]}"
          else
            to = ranges.last[0] - 1 if ranges.any? && to >= ranges.last[0]
            ranges << [from, to, "#{this_period}\##{index}"]
          end
        end
        days -= this_period
        to_date -= this_period
      end
      ranges.reverse
    end

  end
end
