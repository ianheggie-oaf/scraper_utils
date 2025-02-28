# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/scraper_utils/fiber_scheduler"

RSpec.describe ScraperUtils::FiberScheduler do
  before do
    described_class.reset!
  end

  describe ".in_fiber?" do
    it "returns true when running in a registered fiber" do
      executed = false
      fiber = described_class.register_operation("test_authority") do
        executed = described_class.in_fiber?
      end
      fiber.resume
      expect(executed).to be true
    end

    it "returns false when not running in a registered fiber" do
      expect(described_class.in_fiber?).to be false
    end
  end

  describe ".current_authority" do
    it "returns the authority for the current fiber" do
      executed = false
      fiber = described_class.register_operation("test_authority") do
        executed = (described_class.current_authority == "test_authority")
      end
      fiber.resume
      expect(executed).to be true
    end

    it "returns nil when not in a fiber" do
      expect(described_class.current_authority).to be_nil
    end
  end

  describe ".reset!" do
    it "clears registry, exceptions and disables the scheduler" do
      # Set up some state
      described_class.register_operation("test") { Fiber.yield }
      described_class.exceptions["test"] = StandardError.new("Test error")
      described_class.enable!

      # Verify state is set
      expect(described_class.registry).not_to be_empty
      expect(described_class.exceptions).not_to be_empty
      expect(described_class.enabled?).to be true

      # Reset the state
      described_class.reset!

      # Verify state is cleared
      expect(described_class.registry).to be_empty
      expect(described_class.exceptions).to be_empty
      expect(described_class.enabled?).to be false
    end
  end

  describe ".log" do
    it "prefixes log message with authority when in a fiber" do
      expected_output = "[test_authority] Test message\n"
      fiber = described_class.register_operation("test_authority") do
        expect do
          described_class.log("Test message")
        end.to output(expected_output).to_stdout
      end
      fiber.resume
    end

    it "logs without prefix when not in a fiber" do
      expect do
        described_class.log("Test message")
      end.to output("Test message\n").to_stdout
    end
  end

  describe ".find_earliest_fiber" do
    it "returns a fiber without resume time if available" do
      # Create fibers
      fiber1 = described_class.register_operation("auth1") { nil }
      described_class.register_operation("auth2") { nil }
      described_class.register_operation("auth3") { nil }

      # Set resume time for the first fiber
      fiber1.instance_variable_set(:@resume_at, Time.now + 0.5)

      # The second fiber has no resume time, so it should be selected
      earliest = described_class.send(:find_earliest_fiber)
      expect(earliest.instance_variable_get(:@authority)).to eq("auth2")
    end
  end
end
