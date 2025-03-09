# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../lib/scraper_utils/scheduler"

RSpec.describe ScraperUtils::Scheduler do
  let(:fiber_registry) { ScraperUtils::Scheduler.send(:fiber_registry) }
  let(:operations) { fiber_registry.send(:operations) }

  before do
    described_class.reset!
  end

  describe ".parallel?" do
    it "defaults to true" do
      expect(described_class.parallel?).to be true
    end
  end

  describe ".interleaved?" do
    it "defaults to true" do
      expect(described_class.interleaved?).to be true
    end
  end

  describe ".reset!" do
    it "Sets defaults" do
      expect(described_class.interleaved?).to be true
      expect(described_class.send(:exceptions)).to be_a(Hash)
      expect(described_class.send(:delay_requested)).to be 0.0
      expect(described_class.send(:poll_sleep)).to be 0.0
      expect(described_class.send(:resume_count)).to be 0
      expect(described_class.send(:initial_resume_at)).to be_a(Time)
      expect(described_class.send(:fiber_registry)).to be_a(ScraperUtils::Scheduler::FiberRegistry)
      expect(described_class.send(:thread_pool)).to be_a(ScraperUtils::Scheduler::ThreadPool)
      expect(described_class.send(:reset)).to be true
    end
  end

  describe ".register_operation" do
    it "creates a operation and adds it to the operations" do
      expect do
        described_class.register_operation(:test_authority) { :does_nothing }
      end.to change { operations.size }.by(1)
    end

    it "creates an operation with initial state" do
      operation = described_class.register_operation(:test_authority) { :does_nothing }
      expect(operations).to have_key(:test_authority)
      expect(operations).to have_value(operation)

      expect(operation).to be_a(ScraperUtils::Scheduler::FiberOperation)
      expect(operation.authority).to eq(:test_authority)
      expect(operation.alive?).to be true
      expect(operation.ready_to_run?).to be true
      expect(operation.fiber).to be_instance_of(Fiber)
      expect(operation.authority).to be :test_authority
      expect(operation.resume_at).to be_instance_of(Time)
      expect(operation.resume_type).to be :start
      expect(operation.response).to be nil
    end

    it "returns an operation that calls the given block" do
      block_executed = false
      operation = described_class.register_operation(:test_authority) do
        block_executed = true
      end
      operation.resume
      expect(block_executed).to be true
    end

    it "captures exceptions from registered blocks and stores them by authority" do
      operation = described_class.register_operation(:error_authority) do
        raise "Test error"
      end
      operation.resume
      expect(described_class.exceptions).to have_key(:error_authority)
      expect(described_class.exceptions[:error_authority].message).to eq("Test error")
    end

    it "cleans up after operation completion" do
      operation = described_class.register_operation(:test_authority) { :does_nothing }
      expect(operations).to have_key(:test_authority)

      operation.resume

      expect(fiber_registry).to be_empty
      expect(operations).not_to have_key(operation.authority)
    end

    it "cleans up after exception" do
      operation = described_class.register_operation(:error_authority) do
        raise "Test error"
      end
      operation.resume
      expect(fiber_registry).to be_empty
      expect(operations).not_to have_key(operation.authority)
    end
  end

  describe ".run_operations" do
    it "runs all registered fibers to completion" do
      results = []
      described_class.register_operation(:auth1) { results << :auth1 }
      described_class.register_operation(:auth2) { results << :auth2 }

      described_class.run_operations

      expect(results).to contain_exactly(:auth1, :auth2)
      expect(operations).to be_empty
    end

    it "returns exceptions encountered during execution" do
      described_class.register_operation(:auth1) { raise "Error 1" }
      described_class.register_operation(:auth2) { raise "Error 2" }

      exceptions = described_class.run_operations

      expect(exceptions.keys).to contain_exactly(:auth1, :auth2)
      expect(exceptions[:auth1].message).to eq("Error 1")
      expect(exceptions[:auth2].message).to eq("Error 2")
    end

    # FIXME it "processes thread responses before checking for ready fibers" do
    # This test is complex and would require significant setup to properly
    # test the integration between ThreadPool and FiberScheduler
    #
    # We'll skip this for now, but should implement it when implementing
    # the actual integration
    #   pending "FIXME: Complex integration test to be implemented"
    # end
  end

  describe ".execute_requests" do
    pending "FIXME: write specs"
  end

  describe ".delay" do
    pending "FIXME: write specs"
  end

  describe ".current_authority" do
    it "returns the authority for the current operation" do
      executed = nil
      operation = described_class.register_operation(:test_authority) do
        executed = described_class.current_authority
      end
      operation.resume
      expect(executed).to be :test_authority
    end

    it "returns nil when not in a operation" do
      expect(described_class.current_authority).to be_nil
    end
  end

  describe ".find_ready_operation" do
    pending "FIXME: write specs"
  end

  describe ".process_thread_response" do
    pending "FIXME: write specs"
  end

end
