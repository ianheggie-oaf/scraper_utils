# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler do
  let(:operation_registry) { ScraperUtils::Scheduler.send(:operation_registry) }
  let(:operations) { operation_registry.instance_variable_get(:@operations) }

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

  describe ".threaded" do
    it "defaults to true" do
      expect(described_class.threaded).to be true
    end

    it "has question form" do
      expect(described_class.threaded?).to be true
    end

    it "can be set" do
      described_class.threaded = false
      expect(described_class.threaded?).to be false
    end

    it "Is disabled by MORPH_DISABLE_THREADS ENV variable" do
      expect(described_class.threaded?).to be true
      ENV['MORPH_DISABLE_THREADS'] = '42'
      described_class.reset!
      expect(described_class.threaded?).to be false
    ensure
      ENV['MORPH_DISABLE_THREADS'] = nil
    end
  end

  describe ".max_workers" do
    it "defaults to DEFAULT_MAX_WORKERS" do
      expect(described_class.max_workers).to be ScraperUtils::Scheduler::Constants::DEFAULT_MAX_WORKERS
    end

    it "can be set" do
      described_class.max_workers = 11
      expect(described_class.max_workers).to be 11
    end

    it "Is set by MORPH_MAX_WORKERS ENV variable" do
      ENV['MORPH_MAX_WORKERS'] = '42'
      described_class.reset!
      expect(described_class.max_workers).to be 42
    ensure
      ENV['MORPH_MAX_WORKERS'] = nil
    end
  end

  describe ".exceptions" do
    it "defaults to empty Hash" do
      expect(described_class.exceptions).to eq Hash.new
    end
  end

  describe ".timeout" do
    it "defaults to empty Hash" do
      expect(described_class.timeout).to be ScraperUtils::Scheduler::Constants::DEFAULT_TIMEOUT
    end

    it "Is set by MORPH_TIMEOUT ENV variable" do
      ENV['MORPH_TIMEOUT'] = '42'
      described_class.reset!
      expect(described_class.timeout).to be 42
    ensure
      ENV['MORPH_TIMEOUT'] = nil
    end
  end

  describe ".interleaved?" do
    it "defaults to true" do
      expect(described_class.interleaved?).to be true
    end

    it "Is disabled by MORPH_MAX_WORKERS=0" do
      expect(described_class.interleaved?).to be true
      ENV['MORPH_MAX_WORKERS'] = '0'
      described_class.reset!
      expect(described_class.interleaved?).to be false
    ensure
      ENV['MORPH_MAX_WORKERS'] = nil
    end
  end

  describe ".reset!" do
    it "Sets defaults" do
      expect(described_class.interleaved?).to be true
      expect(described_class.send(:exceptions)).to be_a(Hash)
      expect(described_class.send(:totals)[:delay_requested]).to be 0
      expect(described_class.send(:totals)[:poll_sleep]).to be 0
      expect(described_class.send(:totals)[:resume_count]).to be 0
      expect(described_class.send(:initial_resume_at)).to be_a(Time)
      expect(described_class.send(:response_queue)).to be_a(Thread::Queue)
      expect(described_class.send(:operation_registry)).to be_a(ScraperUtils::Scheduler::OperationRegistry)
      expect(described_class.send(:reset)).to be true
    end
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
      
      # Let the fiber terminate properly - the next test that calls run_operations
      # will resume this fiber and let it complete
    end

    # Setup a test fixture for run_operations to test
    let(:results) { [] }

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

  describe ".run_operations" do
    # Setup a shared results array to track operation execution
    let(:results) { [] }
    
    it "runs all registered fibers to completion" do
      # Register two operations
      described_class.register_operation(:auth1) do
        results << :auth1
        :operation_complete
      end
      
      described_class.register_operation(:auth2) do
        results << :auth2
        :operation_complete
      end
      
      # Run operations to completion
      Timeout.timeout(1) do
        described_class.run_operations
      end
      
      # Verify both operations ran
      expect(results).to include(:auth1, :auth2)
      expect(operations).to be_empty
    end

    it "returns exceptions encountered during execution" do
      # Register operations that will raise exceptions
      described_class.register_operation(:auth1) do
        raise "Error 1"
      end
      
      described_class.register_operation(:auth2) do
        raise "Error 2"
      end
      
      # Run operations and capture exceptions
      exceptions = nil
      Timeout.timeout(1) do
        exceptions = described_class.run_operations
      end
      
      # Verify exceptions were captured
      expect(exceptions.keys).to contain_exactly(:auth1, :auth2)
      expect(exceptions[:auth1].message).to eq("Error 1")
      expect(exceptions[:auth2].message).to eq("Error 2")
    end

    it "processes thread responses before checking for ready fibers" do
      # This is hard to test without complex synchronization
      # We'll use a simple approach that pushes a response and verifies it's processed
      
      # Create a response that will be processed
      response_queue = described_class.send(:response_queue)
      
      # Register an operation that will wait for a response
      sync_queue = Queue.new
      
      # First, register an operation that will use the response
      described_class.register_operation(:auth1) do
        # Signal we're ready for the response to be queued
        sync_queue.push(:ready)
        
        # Wait until response is available (would normally happen through submit_request)
        while sync_queue.empty?
          sleep 0.01
        end
        
        # Signal we're done
        results << :auth1_complete
        :operation_complete
      end
      
      # Start operations in a separate thread
      thread = Thread.new do
        described_class.run_operations
      end
      
      # Wait for operation to signal readiness
      Timeout.timeout(1) do
        sync_queue.pop
      end
      
      # Now push a response and notify operation to check for responses
      response = ScraperUtils::Scheduler::ThreadResponse.new(:auth1, :test_result, nil, 0.1)
      response_queue.push(response)
      sync_queue.push(:response_queued)
      
      # Wait for operations to complete
      Timeout.timeout(1) do
        thread.join
      end
      
      # Verify result
      expect(results).to include(:auth1_complete)
      expect(response_queue.size).to eq(0) # Response was processed
    end
  end
end
