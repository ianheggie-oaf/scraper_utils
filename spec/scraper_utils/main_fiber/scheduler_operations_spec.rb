# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler do
  let(:operation_registry) { described_class.send(:operation_registry) }
  let(:operations) { operation_registry.instance_variable_get(:@operations) }
  let(:results) { [] }
  
  # Create a helper to run operations and wait for them to complete
  def run_and_wait(timeout = 1)
    start_time = Time.now
    Thread.new { described_class.run_operations }
    
    # Wait until operations are complete or timeout
    while !operations.empty? && (Time.now - start_time < timeout)
      sleep 0.01
    end
  end

  before do
    described_class.reset!
  end

  describe ".register_operation" do
    it "creates a operation and adds it to the operations" do
      expect do
        described_class.register_operation(:test_authority) do
          # In the worker fiber context
          # We need to properly terminate to allow close() to run
          :operation_complete
        end
      end.to change { operations.size }.by(1)
    end

    # We need to modify this test to check only what we can safely check
    # without breaking validation or requiring new fibers to complete
    it "creates an operation with initial state" do
      op = nil
      
      # Capture the operation for inspection before it runs
      expect do
        op = described_class.register_operation(:test_authority) do
          # Make sure the fiber yields and stays alive for inspection
          Fiber.yield
          :operation_complete
        end
      end.to change { operations.size }.by(1)
      
      # Since we're using a real operation, check what we can safely examine
      expect(operations).to have_key(:test_authority)
      expect(operations[:test_authority]).to eq(op)
      expect(op).to be_a(ScraperUtils::Scheduler::OperationWorker)
      expect(op.authority).to eq(:test_authority)
      expect(op.alive?).to be true
    end

    it "returns an operation that calls the given block" do
      described_class.register_operation(:test_authority) do
        # Running in fiber context
        results << :block_executed
        :operation_complete
      end
      
      # Use a timeout to prevent indefinite blocking
      Timeout.timeout(1) do
        described_class.run_operations
      end
      
      expect(results).to include(:block_executed)
    end

    it "captures exceptions from registered blocks and stores them by authority" do
      described_class.register_operation(:error_authority) do
        # Inside fiber context
        raise "Test error"
      end
      
      # Run operations to completion - exceptions should be captured
      Timeout.timeout(1) do
        described_class.run_operations
      end
      
      # Verify exception was captured
      expect(described_class.exceptions).to have_key(:error_authority)
      expect(described_class.exceptions[:error_authority].message).to eq("Test error")
    end

    it "cleans up after operation completion" do
      # First verify we have an operation
      described_class.register_operation(:test_authority) do
        # This will run in fiber context and then complete
        :operation_complete
      end
      
      expect(operations).to have_key(:test_authority)
      
      # Run to completion
      Timeout.timeout(1) do
        described_class.run_operations
      end
      
      # Verify cleanup happened
      expect(operations).not_to have_key(:test_authority)
    end

    it "cleans up after exception" do
      described_class.register_operation(:error_authority) do
        # This will raise inside fiber context
        raise "Test error" 
      end
      
      expect(operations).to have_key(:error_authority)
      
      # Run to completion - should clean up despite error
      Timeout.timeout(1) do
        described_class.run_operations
      end
      
      # Verify cleanup happened
      expect(operations).not_to have_key(:error_authority)
    end
  end
end
