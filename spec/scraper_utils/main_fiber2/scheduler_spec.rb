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
    it "defaults to DEFAULT_TIMEOUT" do
      expect(described_class.run_timeout).to be ScraperUtils::Scheduler::Constants::DEFAULT_TIMEOUT
    end

    it "Is set by MORPH_RUN_TIMEOUT ENV variable" do
      ENV['MORPH_RUN_TIMEOUT'] = '42'
      described_class.reset!
      expect(described_class.run_timeout).to be 42
    ensure
      ENV['MORPH_RUN_TIMEOUT'] = nil
    end
  end

  describe ".reset!" do
    it "Sets defaults" do
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

  describe ".run_operations" do
    context "with timeouts" do
      before do
        @original_timeout = described_class.run_timeout
      end

      after do
        described_class.run_timeout = @original_timeout
      end

      it "terminates long-running operations after timeout" do
        described_class.run_timeout = 0.2 # 200ms
        exit_queue = Thread::Queue.new
        progress = nil

        # Register a long-running operation and track progress
        described_class.register_operation(:test_timeout) do
          progress = :started
          Timeout.timeout(10) do
            exit_queue.pop
            progress = :interrupted
          end
        end

        allow(ScraperUtils::LogUtils).to receive(:log)
        # Mock Process.exit! to prevent actual exit during test
        allow(Process).to receive(:exit!) do |status|
          exit_queue.push :called
        end

        described_class.run_operations

        expect(Process).to have_received(:exit!).with(124)
        expect(ScraperUtils::LogUtils).to have_received(:log).with(/ERROR: Script exceeded maximum allowed runtime/).once
        expect(progress).to eq(:interrupted)
      end

      it "kills the monitoring thread when operations complete normally" do
        threads_before = Thread.list.dup

        # So something very quick
        described_class.register_operation(:quick_op) { :done }
        described_class.run_operations

        # Verify all threads created during operations are no longer alive
        new_threads = Thread.list - threads_before
        expect(new_threads.select(&:alive?)).to be_empty
      end
    end

    context "with MORPH_MAX_WORKERS=2 and DEBUG=1 set" do
      before do
        @prev_debug = ENV['DEBUG']
        ENV['MORPH_MAX_WORKERS'] = '2'
        ENV['DEBUG'] = '1'
      end

      after do
        ENV['MORPH_MAX_WORKERS'] = nil
        ENV['DEBUG'] = @prev_debug
        described_class.reset!
      end

      it "Runs operations when it hits MORPH_MAX_WORKERS limit" do
        described_class.reset!
        registry = described_class.send(:operation_registry)
        ran = []

        expect(registry.size).to eq(0)
        described_class.register_operation(:test_op1) do
          ran << :test_op1
        end
        expect(registry.size).to eq(1)
        expect(ran).to be_empty
        described_class.register_operation(:test_op2) do
          ran << :test_op2
        end
        expect(registry.size).to eq(0)
        expect(ran).to eq([:test_op1, :test_op2])

        described_class.register_operation(:test_op3) do
          ran << :test_op3
        end
        expect(registry.size).to eq(1)
        expect(ran).to eq([:test_op1, :test_op2])

        described_class.run_operations
        expect(registry.size).to eq(0)
        expect(ran).to eq([:test_op1, :test_op2, :test_op3])
      end

    end
  end
end
