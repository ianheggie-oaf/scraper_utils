# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../lib/scraper_utils/scheduler"

RSpec.describe ScraperUtils::Scheduler do
  let(:operation_registry) { ScraperUtils::Scheduler.send(:operation_registry) }
  let(:operations) { operation_registry.send(:operations) }

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
        described_class.register_operation(:test_authority) { :does_nothing }
      end.to change { operations.size }.by(1)
    end

    it "creates an operation with initial state" do
      operation = described_class.register_operation(:test_authority) { :does_nothing }
      expect(operations).to have_key(:test_authority)
      expect(operations).to have_value(operation)

      expect(operation).to be_a(ScraperUtils::Scheduler::OperationWorker)
      expect(operation.authority).to eq(:test_authority)
      expect(operation.alive?).to be true
      expect(operation.can_resume?).to be true
      expect(operation.fiber).to be_instance_of(Fiber)
      expect(operation.authority).to be :test_authority
      expect(operation.resume_at).to be_instance_of(Time)
      expect(operation.response).to be true
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

      expect(operation_registry).to be_empty
      expect(operations).not_to have_key(operation.authority)
    end

    it "cleans up after exception" do
      operation = described_class.register_operation(:error_authority) do
        raise "Test error"
      end
      operation.resume
      expect(operation_registry).to be_empty
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

    it "processes thread responses before checking for ready fibers" do
      results = []
      op1 = described_class.register_operation(:auth1) do
        results << :auth1
      end
      op2 = described_class.register_operation(:auth2) { results << :auth2 }
      op1.instance_variable_set(:@waiting_for_response, true)
      response = ScraperUtils::Scheduler::ThreadResponse.new(
        :auth1, :a_result, nil, 123.456
      )
      described_class.send(:response_queue).push response

      expect(described_class.send(:response_queue).size).to be 1
      described_class.run_operations
      expect(described_class.send(:response_queue).size).to be 0

      expect(op1.authority).to be :auth1
      expect(op1.response).to be response
      expect(operations).to be_empty
    end
  end


end
