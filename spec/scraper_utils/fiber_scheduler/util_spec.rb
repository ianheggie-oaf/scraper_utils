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
      described_class.enable = true

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

  describe "find_ready_fiber (private method)" do
    let(:executor) { ScraperUtils::FiberScheduler::Executor }
    
    it "finds a fiber with a response ready" do
      # Create fibers
      fiber1 = described_class.register_operation("auth1") { nil }
      fiber2 = described_class.register_operation("auth2") { nil }
      
      # Set response ready for fiber2
      state = described_class.fiber_states[fiber2.object_id]
      state.response = "Test response"
      state.waiting_for_response = false
      
      ready_fiber = executor.send(:find_ready_fiber)
      expect(ready_fiber).to eq(fiber2)
    end
    
    it "finds the earliest fiber due for execution" do
      now = Time.now
      allow(Time).to receive(:now).and_return(now)
      
      # Create fibers with different resume times
      fiber1 = described_class.register_operation("auth1") { nil }
      fiber2 = described_class.register_operation("auth2") { nil }
      
      state1 = described_class.fiber_states[fiber1.object_id]
      state2 = described_class.fiber_states[fiber2.object_id]
      
      state1.resume_at = now + 0.5
      state2.resume_at = now + 0.2
      
      ready_fiber = executor.send(:find_ready_fiber)
      expect(ready_fiber).to eq(fiber2)
    end
  end
end
