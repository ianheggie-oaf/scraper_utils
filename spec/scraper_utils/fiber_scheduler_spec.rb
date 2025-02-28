# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../lib/scraper_utils/fiber_scheduler"

RSpec.describe ScraperUtils::FiberScheduler do
  before do
    described_class.reset!
  end

  describe "integration test" do
    it "interleaves multiple operations" do
      # Create a test class that simulates a scraper with delays
      test_scraper_class = Class.new do
        def initialize(authority, items)
          @authority = authority
          @items = items
        end

        def scrape
          @items.each do |item|
            # Simulate delay between requests
            ScraperUtils::FiberScheduler.delay(0.01)
            yield item
          end
        end
      end

      # Create scrapers for two different authorities
      scraper1 = test_scraper_class.new("Authority1", [1, 2, 3])
      scraper2 = test_scraper_class.new("Authority2", [4, 5, 6])

      # Results will collect items in the order they were processed
      results = []

      # Register both operations
      described_class.register_operation("Authority1") do
        scraper1.scrape do |item|
          results << "Authority1:#{item}"
        end
      end

      described_class.register_operation("Authority2") do
        scraper2.scrape do |item|
          results << "Authority2:#{item}"
        end
      end

      # Run the fibers
      described_class.run_all

      # We should have all items from both authorities
      expect(results.size).to eq(6)

      # The operations should be interleaved
      # This is hard to test deterministically, but we can check that
      # we don't just have all of one authority's items followed by the other
      authority1_items = results.select { |r| r.start_with?("Authority1") }
      authority2_items = results.select { |r| r.start_with?("Authority2") }

      expect(authority1_items.size).to eq(3)
      expect(authority2_items.size).to eq(3)

      # Check that items from each authority are in correct order
      expect(authority1_items).to eq(["Authority1:1", "Authority1:2", "Authority1:3"])
      expect(authority2_items).to eq(["Authority2:4", "Authority2:5", "Authority2:6"])
    end
  end
end
