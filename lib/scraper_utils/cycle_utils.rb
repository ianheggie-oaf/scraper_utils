# frozen_string_literal: true

module ScraperUtils
  # Provides utilities for cycling through a range of options day by day
  module CycleUtils
    # Returns position in cycle from zero onwards
    # @param cycle [Integer] Cycle size (2 onwards)
    # @param date [Date, nil] Optional date to use instead of today
    # @return [Integer] position in cycle progressing from zero to cycle-1 and then repeating day by day
    # Can override using CYCLE_POSITION ENV variable
    def self.position(cycle, date: nil)
      day = ENV.fetch('CYCLE_POSITION', (date || Date.today).jd).to_i
      day % cycle
    end

    # Returns one value per day, cycling through all possible values in order
    # @param values [Array] Values to cycle through
    # @param date [Date, nil] Optional date to use instead of today to calculate position
    # @return value from array
    # Can override using CYCLE_POSITION ENV variable
    def self.pick(values, date: nil)
      values = values.to_a
      values[position(values.size, date: date)]
    end
  end
end
