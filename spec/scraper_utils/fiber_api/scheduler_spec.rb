# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/scraper_utils/scheduler"

RSpec.describe ScraperUtils::Scheduler do
  let(:operation_registry) { ScraperUtils::Scheduler.send(:operation_registry) }
  let(:operations) { operation_registry.send(:operations) }

  before do
    described_class.reset!
  end

  after(:all) do
    if Fiber.current != ScraperUtils::Scheduler::Constants::MAIN_FIBER
      puts "WARNING: Had to resume main fiber"
      ScraperUtils::Scheduler::Constants::MAIN_FIBER.resume
    end
  end

  describe ".execute_request" do
    it "executes operations" do

      result = nil
      described_class.register_operation(:test_authority) do
        result = ScraperUtils::Scheduler.execute_request('aaa', :succ, [])
      end

      described_class.run_operations

      expect(result).to eq 'aab'
    end
  end

  describe ".current_authority" do
    it "returns the authority for the current operation" do
      detected_authority = nil
      executed = false
      operation = described_class.register_operation(:test_authority) do
        executed = true
        detected_authority = described_class.current_authority
      end
      operation.resume
      expect(executed).to be true
      expect(detected_authority).to be :test_authority
    end

    it "returns nil when not in a operation" do
      expect(described_class.current_authority).to be_nil
    end
  end
end
