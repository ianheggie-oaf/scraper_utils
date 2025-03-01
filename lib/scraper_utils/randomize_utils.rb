# frozen_string_literal: true

module ScraperUtils
  # Provides utilities for randomizing processing order in scrapers,
  # particularly helpful for distributing load and avoiding predictable patterns
  module RandomizeUtils
    # Returns a randomized version of the input collection when in production mode,
    # or the original collection when in test/sequential mode
    #
    # @param collection [Array, Enumerable] Collection of items to potentially randomize
    # @return [Array] Randomized or original collection depending on environment
    def self.randomize_order(collection)
      return collection.to_a if sequential?

      collection.to_a.shuffle
    end

    # Checks if sequential processing is enabled
    #
    # @return [Boolean] true when in test mode or MORPH_PROCESS_SEQUENTIALLY is set
    def self.sequential?
      @sequential = !ENV["MORPH_PROCESS_SEQUENTIALLY"].to_s.empty? if @sequential.nil?
      @sequential || false
    end

    # Explicitly set sequential mode for testing
    #
    # @param value [Boolean, nil] true to enable sequential mode, false to disable, nil to clear cache
    # @return [Boolean, nil]
    def self.sequential=(value)
      @sequential = value
    end
  end
end
