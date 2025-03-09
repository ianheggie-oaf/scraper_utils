# frozen_string_literal: true

module ScraperUtils
  # Provides utilities for randomizing processing order in scrapers,
  # particularly helpful for distributing load and avoiding predictable patterns
  module RandomizeUtils
    class << self
      # Controls if processing order can be randomized
      #
      # @return [Boolean] true if all processing is done sequentially, otherwise false
      # @note Defaults to true unless the MORPH_NOT_RANDOM ENV variable is set
      attr_accessor :random

      # Reports if processing order will be randomized
      #
      # @return (see #random)
      alias random? random
    end

    def self.reset!
      @random = ENV["MORPH_NOT_RANDOM"].to_s.empty?
    end

    # reset on class load
    reset!

    # Returns a randomized version of the input collection unless `.sequential?` is true.
    #
    # @param collection [Array, Enumerable] Collection of items
    # @return [Array] Randomized unless {.sequential?} is true, otherwise original order
    def self.randomize_order(collection)
      return collection.to_a.shuffle if random?

      collection.to_a
    end
  end
end
