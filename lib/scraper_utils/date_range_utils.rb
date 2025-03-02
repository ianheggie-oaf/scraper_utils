# frozen_string_literal: true

module ScraperUtils
  class DateRangeUtils

    class << self
      # @return [Boolean] Default number of days to cover
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
      #     config.default_max_period = 3
      #   end
      # @return [void]
      def configure
        yield self if block_given?
      end

      # Reset all configuration options to their default values
      # @return [void]
      def reset_defaults!
        @default_days = ENV.fetch('MORPH_DAYS', 30).to_i # 30
        @default_everytime = ENV.fetch('MORPH_EVERYTIME', 2).to_i # 2
        @default_max_period = ENV.fetch('MORPH_MAX_PERIOD', 7).to_i # 7
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
      if !max_period.positive? || !days.positive?
        return []
      elsif max_period == 1 || everytime >= days
        # cover everything everytime
        return [[today + 1 - days, today, "everything"]]
      end

      run_number = today.to_date.jd
      ranges = []
      if everytime.positive?
        # add one day to cover running yesterday before work hours and then today after work hours
        ranges << [to_date - everytime, to_date, "everytime"]
        days -= everytime
        to_date -= everytime
      end

      last_fibonacci = period = 1
      loop do
        last_fibonacci, period = [period, last_fibonacci + period]
        break if period > max_period || !days.positive?

        period_start_date = to_date
        # puts "DEBUG: #{period} day periods started #{(today - to_date).to_i} days in."
        @max_period_used = period
        period.times do |index|
          break unless days.positive?

          this_period = [days, period].min
          # we are working from the oldest back towards today
          if run_number % period == index
            from = to_date - index - (this_period - 1)
            extending = index == 0  ? 'E' : nil
            to = [today, to_date - index + (extending ? last_fibonacci : 0)].min
            puts "DEBUG    Note: To date extended by #{last_fibonacci} days from #{this_period} days long  ##{index}" if extending
            if ranges.any? && ranges.last[0] <= to + 1
              # extend adjacent range
              ranges.last[0] = [from, ranges.last[0]].min
              ranges.last[2] = "#{period}#{extending}\##{index},#{ranges.last[2]}"
            else
              ranges << [from, to, "#{period}#{extending}\##{index}"]
            end
          end
          days -= this_period
          to_date -= this_period
        end
      end
      # remainder of range at max_period, whatever that is
      # puts "DEBUG: #{max_period} day periods started #{(today - to_date).to_i} days in." if days.positive?
      index = -1
      last_fibonacci = @max_period_used
      last_fibonacci = 0 if last_fibonacci == max_period
      while days.positive?
        index += 1
        index = 0 if index >= max_period
        this_period = [days, max_period].min
        if run_number % max_period == index
          @max_period_used = [this_period, @max_period_used].max
          from = to_date - index - (this_period - 1)
          extending = (index == 0 && last_fibonacci.positive?) ? 'E' : nil
          to = to_date - index + (extending ? last_fibonacci : 0)
          puts "DEBUG    Note: To date extended by #{last_fibonacci} days from #{this_period} days long ##{index}" if extending
          if ranges.any? && ranges.last[0] <= to + 1
            # extend adjacent range
            ranges.last[0] = [from, ranges.last[0]].min
            ranges.last[2] = "#{this_period}#{extending}\##{index},#{ranges.last[2]}"
          else
            ranges << [from, to, "#{this_period}#{extending}\##{index}"]
          end
        end
        days -= this_period
        to_date -= this_period
      end
      ranges.reverse
    end

  end
end
