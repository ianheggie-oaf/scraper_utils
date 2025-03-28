# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler do
  context "With threads disabled" do
    let(:operation_registry) { described_class.send(:operation_registry) }
    let(:operations) { operation_registry.instance_variable_get(:@operations) }
    let(:results) { [] }

    before do
      @prev_disable_random = ENV['MORPH_DISABLE_RANDOM']
      @prev_disable_threads = ENV['MORPH_DISABLE_THREADS']
      @prev_max_workers = ENV['MORPH_MAX_WORKERS']
      ENV['MORPH_DISABLE_RANDOM'] = '1'
      ENV['MORPH_DISABLE_THREADS'] = '1'
      ENV['MORPH_MAX_WORKERS'] = '1'
      described_class.reset!
    end

    after(:all) do
      ENV['MORPH_DISABLE_RANDOM'] = @prev_disable_random
      ENV['MORPH_DISABLE_THREADS'] = @prev_disable_threads
      ENV['MORPH_MAX_WORKERS'] = @prev_max_workers
      if Fiber.current != ScraperUtils::Scheduler::Constants::MAIN_FIBER
        puts "WARNING: Had to resume main fiber"
        ScraperUtils::Scheduler::Constants::MAIN_FIBER.resume
      end
    end

    describe ".register_operation" do
      it "creates a operation and runs it immediately" do
        expect do
          described_class.register_operation(:test_authority) do
            expect(operations.size).to eq(1)
            expect(operations[:test_authority]).to be_a(ScraperUtils::Scheduler::OperationWorker)
            expect(operations[:test_authority].thread).to be_nil
            # In the worker fiber context
            # We need to properly terminate to allow close() to run
            :operation_complete
          end
        end.not_to change { operations.size }
        expect(operations).to be_empty
      end

      it "captures exceptions from registered blocks and stores them by authority" do
        Timeout.timeout(1) do
          described_class.register_operation(:error_authority) do
            # Inside fiber context
            raise "Test error"
          end
        end

        # Verify exception was captured
        expect(described_class.exceptions).to have_key(:error_authority)
        expect(described_class.exceptions[:error_authority].message).to eq("Test error")

        expect(operations).to be_empty
      end
    end
  end
end

