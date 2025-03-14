# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler do
  let(:operation_registry) { described_class.send(:operation_registry) }
  let(:operations) { operation_registry.instance_variable_get(:@operations) }

  before do
    described_class.reset!
  end

  after(:all) do
    if Fiber.current != ScraperUtils::Scheduler::Constants::MAIN_FIBER
      puts "WARNING: Had to resume main fiber"
      ScraperUtils::Scheduler::Constants::MAIN_FIBER.resume
    end
    # Make sure we don't leave operations running
    operation_registry.shutdown if operation_registry
  end

  describe ".threaded" do
    it "has configurable threading settings" do
      # Test defaults
      expect(described_class.threaded?).to be true

      # Test setting via properties
      described_class.threaded = false
      expect(described_class.threaded?).to be false
    end
  end

  describe ".register_operation" do
    it "registers operations that execute their blocks" do
      executed = false

      described_class.register_operation(:test_op) do
        executed = true
        :done
      end

      # Run operations to completion
      Timeout.timeout(1) do
        described_class.run_operations
      end

      expect(executed).to be true
    end
  end
end
