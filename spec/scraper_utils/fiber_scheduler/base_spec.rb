# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/scraper_utils/fiber_scheduler"

RSpec.describe ScraperUtils::Scheduler do
  before do
    described_class.reset!
  end

  describe ".register_operation" do
    it "creates a fiber and adds it to the registry" do
      expect do
        described_class.register_operation("test_authority") { :does_nothing }
      end.to change { described_class.registry.size }.by(1)
    end

    it "automatically enables fiber scheduling" do
      expect(described_class.enabled?).to be false
      described_class.register_operation("test_authority") { :does_nothing }
      expect(described_class.enabled?).to be true
    end

    it "executes the given block in a fiber" do
      block_executed = false
      fiber = described_class.register_operation("test_authority") do
        block_executed = true
      end
      fiber.resume
      expect(block_executed).to be true
    end

    it "stores the authority with the fiber" do
      executed = false
      fiber = described_class.register_operation("test_authority") do
        executed = (described_class.current_authority == "test_authority")
      end
      fiber.resume
      expect(executed).to be true
    end

    it "captures exceptions and stores them by authority" do
      fiber = described_class.register_operation("error_authority") do
        raise "Test error"
      end
      fiber.resume
      expect(described_class.exceptions).to have_key("error_authority")
      expect(described_class.exceptions["error_authority"].message).to eq("Test error")
    end

    it "removes the fiber from registry after completion" do
      fiber = described_class.register_operation("test_authority") { :does_nothing }
      expect(described_class.registry).to include(fiber)
      fiber.resume
      expect(described_class.registry).to be_empty
    end

    it "removes the fiber from registry even after exception" do
      fiber = described_class.register_operation("error_authority") do
        raise "Test error"
      end
      fiber.resume
      expect(described_class.registry).to be_empty
    end
  end

  describe ".run_all" do
    it "runs all registered fibers to completion" do
      results = []
      described_class.register_operation("auth1") { results << "auth1" }
      described_class.register_operation("auth2") { results << "auth2" }

      described_class.run_all

      expect(results).to contain_exactly("auth1", "auth2")
      expect(described_class.registry).to be_empty
    end

    it "returns exceptions encountered during execution" do
      described_class.register_operation("auth1") { raise "Error 1" }
      described_class.register_operation("auth2") { raise "Error 2" }

      exceptions = described_class.run_all

      expect(exceptions.keys).to contain_exactly("auth1", "auth2")
      expect(exceptions["auth1"].message).to eq("Error 1")
      expect(exceptions["auth2"].message).to eq("Error 2")
    end
  end
end
