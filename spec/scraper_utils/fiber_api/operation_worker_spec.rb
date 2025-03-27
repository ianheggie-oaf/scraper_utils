# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }

  after(:all) do
    if Fiber.current != ScraperUtils::Scheduler::Constants::MAIN_FIBER
      puts "WARNING: Had to resume main fiber"
      ScraperUtils::Scheduler::Constants::MAIN_FIBER.resume
    end
  end

  describe "#submit_request" do
    it "raises error if already waiting for response" do
      # Create a fiber for this test
      fiber = Fiber.new do |action|
        action.is_a?(Proc) ? action.call : action
      end

      worker = described_class.new(fiber, authority, response_queue)
      worker.instance_variable_set(:@waiting_for_response, true)

      expect { fiber.resume(-> {
        worker.submit_request(TestThreadRequest.new(authority))
      }) }
        .to raise_error(ScraperUtils::Scheduler::OperationWorker::NotReadyError, /Cannot make a second request/)
    end

    it "raises error if request is not a ThreadRequest" do
      fiber = Fiber.new do |action|
        action.is_a?(Proc) ? action.call : action
      end

      worker = described_class.new(fiber, authority, response_queue)

      expect { fiber.resume(-> {
        worker.submit_request("not a thread request")
      }) }
        .to raise_error(ArgumentError, /Must be passed a valid ThreadRequest/)
    end

    context "with request queue (parallel processing enabled)" do
      it "processes request through thread and queue" do
        fiber = Fiber.new do |action|
          action.is_a?(Proc) ? action.call : action
        end

        worker = described_class.new(fiber, authority, response_queue)
        request = TestThreadRequest.new(authority, result: :test_result)

        # Start a thread to capture the response
        thread = Thread.new do
          response_queue.pop
        end

        # Run in fiber context
        fiber.resume(-> {
          worker.submit_request(request)
        })

        # Get the response from our thread
        response = thread.value

        expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
        expect(response.authority).to eq(authority)
        expect(response.result).to eq(:test_result)
        expect(response.error).to be_nil
        expect(worker.instance_variable_get(:@waiting_for_response)).to be true
      end
    end

    context "without request queue (parallel disabled)" do
      it "processes request directly without thread" do
        fiber = Fiber.new do |action|
          action.is_a?(Proc) ? action.call : action
        end

        worker = described_class.new(fiber, authority, nil)
        request = TestThreadRequest.new(authority, result: :direct_result)

        result = fiber.resume(-> {
          worker.submit_request(request)
        })

        expect(request.executed).to be true
        expect(result).to be_a(ScraperUtils::Scheduler::ThreadResponse)
        expect(result.result).to eq(:direct_result)
        expect(result.error).to be_nil
      end

      it "handles errors in direct processing" do
        fiber = Fiber.new do |action|
          action.is_a?(Proc) ? action.call : action
        end

        worker = described_class.new(fiber, authority, nil)
        test_error = RuntimeError.new("Test error")
        request = TestThreadRequest.new(authority, error: test_error)

        result = fiber.resume(-> {
          worker.submit_request(request)
        })

        expect(request.executed).to be true
        expect(result).to be_a(ScraperUtils::Scheduler::ThreadResponse)
        expect(result.error).to eq(test_error)
        expect(result.success?).to be false
      end

      it "passes delay_till from request to response" do
        fiber = Fiber.new do |action|
          action.is_a?(Proc) ? action.call : action
        end

        worker = described_class.new(fiber, authority, nil)
        future_time = Time.now + 10
        request = TestThreadRequest.new(authority, delay_till: future_time)

        result = fiber.resume(-> {
          worker.submit_request(request)
        })

        expect(result.delay_till).to eq(future_time)
      end
    end
  end

  describe "#close" do
    it "releases resources and clears state from within worker fiber" do
      worker = nil
      fiber = Fiber.new do
        worker&.close
        :the_end
      end
      worker = described_class.new(fiber, authority, response_queue)

      expect(worker.request_queue).to be_a(Thread::Queue)
      expect(worker.thread).to be_a(Thread)
      worker.instance_variable_set(:@resume_at, :a_resume_at)
      worker.instance_variable_set(:@response, :some_response)
      worker.instance_variable_set(:@waiting_for_response, :waiting)

      expect(fiber.resume).to eq(:the_end)

      # check resources are released and state cleared
      expect(worker.request_queue).to be_nil
      expect(worker.thread).to be_nil
      expect(worker.resume_at).to be_nil
      expect(worker.response).to be_nil
      expect(worker.waiting_for_response).to be false
    end

    it "raises error if called from main fiber" do
      fiber = Fiber.new { :the_end }

      worker = described_class.new(fiber, authority, response_queue)

      # Call close from main fiber - this should raise an error
      expect { worker.close }.to raise_error(ArgumentError, /Must be run within the worker not main fiber/)
    end
  end

  describe "#validate_fiber" do
    it "raises error when in wrong fiber context" do
      worker = nil
      test_fiber = Fiber.new do
        worker.send(:validate_fiber, main: true)
      end
      worker = described_class.new(test_fiber, authority, response_queue)

      expect { test_fiber.resume }.to raise_error(ArgumentError, /Must be run within the main not worker fiber/)

      # When called with main: false from main fiber, should raise error
      expect {
        worker.send(:validate_fiber, main: false)
      }.to raise_error(ArgumentError, /Must be run within the worker not main fiber/)
    end

    it "doesn't raise error when in correct fiber context" do
      worker = nil
      test_fiber = Fiber.new do
        worker.send(:validate_fiber, main: false)
      end
      worker = described_class.new(test_fiber, authority, response_queue)

      expect(test_fiber.resume).to be_nil
      # When called with main: false from main fiber, should raise error
      expect(worker.send(:validate_fiber, main: true)).to be_nil
    end
  end
end
