# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }
  let(:worker_fiber) { Fiber.new { Fiber.yield } } # Use Fiber.yield to keep fiber alive

  after(:all) do
    if Fiber.current != ScraperUtils::Scheduler::Constants::MAIN_FIBER
      puts "WARNING: Had to resume main fiber"
      ScraperUtils::Scheduler::Constants::MAIN_FIBER.resume
    end
  end

  describe "#shutdown" do
    it "clears resume state" do
      worker = described_class.new(worker_fiber, authority, response_queue)

      # Set some initial state
      worker.resume_at = Time.now + 10
      worker.response = :some_response
      worker.instance_variable_set(:@waiting_for_response, true)

      worker.shutdown

      # Verify state is cleared
      expect(worker.resume_at).to be_nil
      expect(worker.response).to be_nil
      expect(worker.instance_variable_get(:@waiting_for_response)).to be false
    end

    it "resumes fiber with nil if fiber is alive" do
      alive_fiber = Fiber.new { Fiber.yield }
      alive_fiber.resume # Start fiber but leave it alive

      worker = described_class.new(alive_fiber, authority, response_queue)

      # Check if resume is called with nil
      expect(alive_fiber).to receive(:resume).with(nil)

      worker.shutdown
    end

    it "raises error if called from worker fiber" do
      # Create a fiber to run the test
      test_fiber = Fiber.new do
        _worker = described_class.new(Fiber.current, authority, response_queue)
      end

      # Run the test
      expect { test_fiber.resume }
        .to raise_error(ArgumentError, /Must be run within main fiber/)
    end
  end

  describe "#resume" do
    it "raises error if fiber is not alive" do
      dead_fiber = Fiber.new { :done }
      dead_fiber.resume # Exhaust the fiber
      worker = described_class.new(dead_fiber, authority, response_queue)

      expect { worker.resume }.to raise_error(ClosedQueueError)
    end

    it "raises error if no response is available" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      worker.instance_variable_set(:@response, nil)

      expect { worker.resume }.to raise_error(ScraperUtils::Scheduler::OperationWorker::NotReadyError)
    end

    it "resumes fiber with response and returns request" do
      test_request = TestThreadRequest.new(authority)
      test_fiber = Fiber.new do |response|
        expect(response).to eq(:test_response)
        test_request
      end

      worker = described_class.new(test_fiber, authority, response_queue)
      worker.instance_variable_set(:@response, :test_response)

      # Allow submit_request for proper processing of the returned request
      allow(worker).to receive(:submit_request)

      request = worker.resume

      expect(request).to eq(test_request)
    end

    it "submits returned request when non-nil" do
      test_request = TestThreadRequest.new(authority)
      test_fiber = Fiber.new { |response| test_request }
      worker = described_class.new(test_fiber, authority, response_queue)

      # Track if submit_request is called
      expect(worker).to receive(:submit_request).with(test_request)

      worker.resume
    end

    it "doesn't submit request when nil" do
      test_fiber = Fiber.new { |response| nil }
      worker = described_class.new(test_fiber, authority, response_queue)

      # Track that submit_request is not called
      expect(worker).not_to receive(:submit_request)

      worker.resume
    end
  end
end
