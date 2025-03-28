# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::MechanizeUtils::AdaptiveDelay do
  # before do
  #   # Reset the delay cache before each test
  #   described_class.new.instance_variable_set(:@delays, {})
  # end

  describe "#initialize" do
    it "sets initial delay to a float" do
      delay_handler = described_class.new(min_delay: 0.5)
      expect(delay_handler.min_delay).to be_a(Float)
      expect(delay_handler.min_delay).to eq(0.5)
    end

    it "uses default values when not provided" do
      delay_handler = described_class.new
      expect(delay_handler.max_delay).to eq(ScraperUtils::MechanizeUtils::AdaptiveDelay::DEFAULT_MAX_DELAY)
    end

    it "accepts custom max_delay" do
      delay_handler = described_class.new(max_delay: 60.0)
      expect(delay_handler.max_delay).to eq(60.0)
    end
  end

  describe "#next_delay" do
    let(:delay_handler) { described_class.new(min_delay: 1.0, max_delay: 30.0) }
    let(:test_url) { "https://example.com/test" }

    it "uses 4x first response time as initial delay" do
      delay = delay_handler.next_delay(test_url, 1.5)
      expect(delay).to eq(1.5) # 1.5 * 4.0
    end

    it "Handles negative response times due to clock skew sanely" do
      delay = delay_handler.next_delay(test_url, -30.0)
      expect(delay).to eq(1.0) # Clamped to min_delay
      delay = delay_handler.next_delay(test_url, 2.5)
      expect(delay).to be_within(0.1).of(1.375) # start to come up immediately
    end

    it "Handles huge response times due to clock skew sanely" do
      delay = delay_handler.next_delay(test_url, 999.0)
      expect(delay).to eq(30.0) # Clamped to max_delay
      delay = delay_handler.next_delay(test_url, 1.0)
      expect(delay).to be_within(0.1).of(22.75) # start to come down immediately
    end

    it "trends 25% towards 4x response time each call" do
      # Multiple calls should trend towards 4x the response time
      trend = delay_handler.next_delay(test_url, 1.0)
      expect(trend).to be_within(0.1).of(1.0)
      10.times do
        delay = delay_handler.next_delay(test_url, 2.0)
        trend = (2.0 + 3 * trend) / 4.0
        expect(delay).to be_within(0.1).of(trend)
      end
    end

    it "restricts min delay value" do
      min_delay = delay_handler.next_delay(test_url, 0.1)
      expect(min_delay).to eq(1.0) # Clamped to min_delay
    end

    it "restricts max delay value" do
      max_delay = delay_handler.next_delay(test_url, 99.0)
      expect(max_delay).to eq(30.0) # Clamped to max_delay
    end

    context "with debug environment" do
      before { ENV["DEBUG"] = "true" }
      after { ENV.delete("DEBUG") }

      it "prints delay change when in debug mode" do
        expect { delay_handler.next_delay(test_url, 2.0) }
          .to output(%r{Adaptive delay for https://example.com updated to}).to_stdout
      end
    end
  end

  describe "#domain" do
    let(:delay_handler) { described_class.new }

    it "extracts domain from URL string" do
      expect(delay_handler.send(:domain, "https://example.com/path")).to eq("https://example.com")
    end

    it "extracts domain from URI object" do
      uri = URI("https://example.com/path")
      expect(delay_handler.send(:domain, uri)).to eq("https://example.com")
    end

    it "normalizes domain to lowercase" do
      expect(delay_handler.send(:domain, "HTTPS://EXAMPLE.COM/path")).to eq("https://example.com")
    end
  end

  describe "#delay" do
    let(:delay_handler) { described_class.new(min_delay: 1.0) }
    let(:test_url) { "https://example.com/test" }

    it "returns min_delay for unknown domains" do
      expect(delay_handler.delay(test_url)).to eq(1.0)
    end

    it "returns current delay for known domains" do
      delay_handler.next_delay(test_url, 1.0) # Sets up initial delay
      expect(delay_handler.delay(test_url)).to be_within(0.1).of(1.0)
    end
  end

  describe "caching behavior" do
    let(:delay_handler) { described_class.new(min_delay: 1.0, max_delay: 30.0) }
    let(:test_url1) { "https://example.com/test1" }
    let(:test_url2) { "https://example.com/test2" }
    let(:test_other_url) { "https://other.com/test" }

    it "caches delays per domain" do
      # Same domain should share delay
      delay1 = delay_handler.next_delay(test_url1, 1.0)
      delay2 = delay_handler.next_delay(test_url2, 2.0)
      expect(delay2).not_to eq(2.0) # Not 4 * 2.0
      expect(delay2).to be_within(0.1).of(1.25)
    end

    it "maintains separate caches for different domains" do
      # Different domains should have independent delays
      delay1 = delay_handler.next_delay(test_url1, 1.0)
      expect(delay1).to eq(1.0) # Should be 4 * 1.0 for test domain
      delay2 = delay_handler.next_delay(test_other_url, 2.0)
      expect(delay2).to eq(2.0) # Should be 4 * 2.0 for new domain
    end

    it "persists delays between calls" do
      initial_delay = delay_handler.next_delay(test_url1, 1.0)
      stored_delay = delay_handler.delay(test_url1)
      expect(stored_delay).to eq(initial_delay)
    end
  end
end
