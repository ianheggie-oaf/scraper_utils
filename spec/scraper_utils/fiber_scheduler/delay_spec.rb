# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/scraper_utils/fiber_scheduler"

RSpec.describe ScraperUtils::FiberScheduler do
  before do
    described_class.reset!
  end

  describe ".delay" do
    context "when fiber scheduling is disabled" do
      it "falls back to regular sleep" do
        described_class.enable = false
        expect(described_class).to receive(:sleep).with(0.1)
        described_class.delay(0.1)
      end
    end

    context "when registry is empty" do
      it "falls back to regular sleep" do
        described_class.enable = true
        expect(described_class).to receive(:sleep).with(0.1)
        described_class.delay(0.1)
      end
    end

    context "with only one fiber" do
      it "falls back to regular sleep" do
        # Setup a fiber but don't let it complete
        test_fiber = Fiber.new { Fiber.yield }
        ScraperUtils::FiberScheduler::Registry.registry << test_fiber
        described_class.enable = true

        # Mock current_fiber to be the same as our test_fiber
        allow(Fiber).to receive(:current).and_return(test_fiber)

        expect(described_class).to receive(:sleep).with(0.1)
        described_class.delay(0.1)
      end
    end

    context "with multiple fibers" do
      it "switches to another fiber if available" do
        described_class.enable = true

        # Array to track the execution sequence
        work_done = []

        # Register two fibers with operations
        described_class.register_operation("first") do
          work_done << "First authority part one"
          described_class.delay(0.01)
          work_done << "First authority part two"
        end

        described_class.register_operation("second") do
          work_done << "Second authority part one"
          described_class.delay(0.01)
          work_done << "Second authority part two"
        end

        # Run all fibers
        described_class.run_all

        # Check that the operations were interleaved correctly
        expect(work_done).to eq([
                                  "First authority part one",
                                  "Second authority part one",
                                  "First authority part two",
                                  "Second authority part two"
                                ])
      end

      it "respects wake-up order for scheduling" do
        described_class.enable = true

        # Track execution order
        work_done = []

        # Register fibers with varying delay times
        described_class.register_operation("quick") do
          work_done << "Quick task started"
          described_class.delay(0.01)
          work_done << "Quick task finished"
        end

        described_class.register_operation("slow") do
          work_done << "Slow task started"
          described_class.delay(0.03)
          work_done << "Slow task finished"
        end

        described_class.register_operation("medium") do
          work_done << "Medium task started"
          described_class.delay(0.02)
          work_done << "Medium task finished"
        end

        # Run all fibers
        described_class.run_all

        # Tasks should start in registration order, but finish in order of delay time
        expect(work_done).to eq([
                                  "Quick task started",
                                  "Slow task started", 
                                  "Medium task started",
                                  "Quick task finished",
                                  "Medium task finished",
                                  "Slow task finished" 
                                ])
      end
    end
  end
end
