# frozen_string_literal: true

require "scraperwiki"

module ScraperUtils
  # Misc Maths Utilities
  module MathsUtils
    # Generate a fibonacci series
    # @param max [Integer] The max the sequence goes up to
    # @return [Array<Integer>] The fibonacci numbers up to max
    def self.fibonacci_series(max)
      result = []
      # Start with the basic Fibonacci sequence
      last_fib, this_fib = 1, 0
      while this_fib <= max
        result << this_fib
        yield this_fib if block_given?
        last_fib, this_fib = this_fib, this_fib + last_fib
      end
      result
    end
  end
end
