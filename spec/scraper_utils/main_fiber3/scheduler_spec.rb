# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler do
  before do
    described_class.reset!
  end

  after(:all) do
    if Fiber.current != ScraperUtils::Scheduler::Constants::MAIN_FIBER
      puts "WARNING: Had to resume main fiber"
      ScraperUtils::Scheduler::Constants::MAIN_FIBER.resume
    end
  end

  describe ".get_response" do
    it "returns nil when queue is empty and non_block is true" do
      # Access the private method for testing
      response = described_class.send(:get_response, true)
      expect(response).to be_nil
    end

    it "returns response from queue when available" do
      # Create a response and add it to the queue
      response_queue = described_class.send(:response_queue)
      test_response = ScraperUtils::Scheduler::ThreadResponse.new(
        :test_authority, "result", nil, 0.1
      )
      response_queue.push(test_response)

      # Get the response
      response = described_class.send(:get_response, true)
      expect(response).to eq(test_response)
    end
  end

  describe ".save_thread_responses" do
    it "processes all responses in the queue" do
      # Set up the response queue with multiple responses
      response_queue = described_class.send(:response_queue)

      # Create test responses
      test_responses = [
        ScraperUtils::Scheduler::ThreadResponse.new(:auth1, "result1", nil, 0.1),
        ScraperUtils::Scheduler::ThreadResponse.new(:auth2, "result2", nil, 0.2),
        ScraperUtils::Scheduler::ThreadResponse.new(:auth3, "result3", nil, 0.3)
      ]

      # Add responses to queue
      test_responses.each { |resp| response_queue.push(resp) }

      # Mock the operation registry to verify it processes the responses
      operation_registry = described_class.send(:operation_registry)
      allow(operation_registry).to receive(:find).and_return(nil) # Return nil to simulate not finding operations

      # Call the method
      described_class.send(:save_thread_responses)

      # Verify all responses were processed
      expect(response_queue.empty?).to be true

      # Verify find was called for each response
      expect(operation_registry).to have_received(:find).exactly(test_responses.size).times
    end
  end

  describe ".resume_next_operation" do
    context "when no operations are ready" do
      it "sleeps for the poll period" do
        # Mock operation registry with empty can_resume
        operation_registry = described_class.send(:operation_registry)
        allow(operation_registry).to receive(:can_resume).and_return([])

        # Expect sleep to be called with POLL_PERIOD
        expect(described_class).to receive(:sleep).with(ScraperUtils::Scheduler::Constants::POLL_PERIOD)

        # Call the method
        described_class.send(:resume_next_operation)

        # Verify totals were updated
        totals = described_class.send(:totals)
        expect(totals[:wait_response]).to eq(ScraperUtils::Scheduler::Constants::POLL_PERIOD)
      end
    end

    context "with a ready operation" do
      it "resumes the operation when resume_at is in the past" do
        # Create a test operation that's ready to resume
        operation = double(
          "OperationWorker",
          alive?: true,
          resume_at: Time.now - 1, # In the past
          resume: nil
        )

        # Mock operation registry
        operation_registry = described_class.send(:operation_registry)
        allow(operation_registry).to receive(:can_resume).and_return([operation])

        # Call the method
        described_class.send(:resume_next_operation)

        # Verify resume was called on the operation
        expect(operation).to have_received(:resume)

        # Verify totals were updated
        totals = described_class.send(:totals)
        expect(totals[:resume_count]).to eq(1)
      end

      it "waits if resume_at is in the future" do
        # Create a test operation that is in the future
        worker = ScraperUtils::Scheduler.register_operation(:future_op) { :the_end }
        worker.instance_variable_set(:@resume_at, Time.now + 900)

        # Expect sleep to be called with delay (capped at POLL_PERIOD)
        expect(described_class).to receive(:sleep).with(ScraperUtils::Scheduler::Constants::POLL_PERIOD)
        expect(worker).not_to receive(:resume)

        # Call the method
        described_class.send(:resume_next_operation)

        # Verify totals were updated
        totals = described_class.send(:totals)
        expect(totals[:wait_delay]).to eq(ScraperUtils::Scheduler::Constants::POLL_PERIOD)
      end

      it "removes dead operations from the registry" do
        worker = ScraperUtils::Scheduler.register_operation(:dead_op) { :replace_me }

        broken_fiber = Fiber.new { :the_end }
        worker.instance_variable_set(:@fiber, broken_fiber)

        registry = described_class.send(:operation_registry)

        # resume broken_fiber so it exits
        expect(broken_fiber.resume).to eq(:the_end)

        # the dead fiber won't have been detected yet
        expect(registry.empty?).to be false

        # Verify log was called about removing the dead operation
        expect(ScraperUtils::LogUtils).to receive(:log).with(/removing dead operation/)

        # Call the method
        described_class.send(:resume_next_operation)

        # Make sure it actually removed the dead operation
        expect(registry.empty?).to be true
      end
    end
  end

  describe ".report_summary" do
    it "reports statistics on scheduler activity" do
      # Set up totals with test values
      totals = described_class.send(:totals)
      totals[:resume_count] = 42
      totals[:wait_delay] = 22
      totals[:wait_response] = 66

      # Expect log to be called with stats
      expect(ScraperUtils::LogUtils).to receive(:log) do |message|
        expect(message).to include("processed 42 calls for 5 registrations")
        expect(message).to include("with 25.0% of 88 seconds spent keeping under max_load")
        expect(message).to include("and 75.0% waiting for network I/O requests")
      end

      # Call the method
      described_class.send(:report_summary, 5) # 5 operations
    end
  end
end
