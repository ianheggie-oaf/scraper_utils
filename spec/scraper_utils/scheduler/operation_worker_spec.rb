# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }
  let(:main_fiber) { ScraperUtils::Scheduler::Constants::MAIN_FIBER }
  let(:worker_fiber) { Fiber.new { :worker_fiber } }

  describe "#initialize" do
    it "creates a valid operation worker" do
      allow(Fiber).to receive(:current).and_return(main_fiber)
      
      worker = described_class.new(worker_fiber, authority, response_queue)
      
      expect(worker.fiber).to eq(worker_fiber)
      expect(worker.authority).to eq(authority)
      expect(worker.can_resume?).to be true
      expect(worker.response).to be true
      expect(worker.instance_variable_get(:@request_queue)).to be_a(Thread::Queue)
      expect(worker.instance_variable_get(:@thread)).to be_a(Thread)
    end

    it "raises error if called from non-main fiber" do
      allow(Fiber).to receive(:current).and_return(Fiber.new { :wrong_fiber })
      
      expect { 
        described_class.new(worker_fiber, authority, response_queue) 
      }.to raise_error(ArgumentError, /Must be run within main fiber/)
    end
    
    it "raises error if fiber or authority is missing" do
      allow(Fiber).to receive(:current).and_return(main_fiber)
      
      expect { described_class.new(nil, authority, response_queue) }.to raise_error(ArgumentError)
      expect { described_class.new(worker_fiber, nil, response_queue) }.to raise_error(ArgumentError)
    end
    
    it "sets initial state with resume_at in the future" do
      allow(Fiber).to receive(:current).and_return(main_fiber)
      worker = described_class.new(worker_fiber, authority, response_queue)
      
      expect(worker.resume_at).to be >= Time.now - 0.1 # Allow small time variance
      expect(worker.instance_variable_get(:@waiting_for_response)).to be false
    end
    
    it "creates next resume time with small offset" do
      allow(Fiber).to receive(:current).and_return(main_fiber)
      first_time = described_class.next_resume_at
      second_time = described_class.next_resume_at
      
      expect(second_time - first_time).to be_within(0.0001).of(0.001)
    end
  end
  
  describe "#alive?" do
    before do
      allow(Fiber).to receive(:current).and_return(main_fiber)
    end
    
    it "returns true when fiber is alive" do
      alive_fiber = Fiber.new { Fiber.yield }
      worker = described_class.new(alive_fiber, authority, response_queue)
      
      expect(worker.alive?).to be true
    end
    
    it "returns false when fiber is dead" do
      dead_fiber = Fiber.new { :done }
      dead_fiber.resume # Exhaust the fiber
      worker = described_class.new(dead_fiber, authority, response_queue)
      
      expect(worker.alive?).to be false
    end
  end
  
  describe "#can_resume?" do
    before do
      allow(Fiber).to receive(:current).and_return(main_fiber)
    end
    
    it "returns false if no response is available" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      worker.instance_variable_set(:@response, nil)
      
      expect(worker.can_resume?).to be false
    end
    
    it "returns false if fiber is not alive" do
      dead_fiber = Fiber.new { :done }
      dead_fiber.resume # Exhaust the fiber
      worker = described_class.new(dead_fiber, authority, response_queue)
      
      expect(worker.can_resume?).to be false
    end
    
    it "returns true when response is available and fiber is alive" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      
      expect(worker.can_resume?).to be true
    end
  end
  
  describe "#save_thread_response" do
    before do
      allow(Fiber).to receive(:current).and_return(main_fiber)
    end
    
    let(:worker) { described_class.new(worker_fiber, authority, response_queue) }
    let(:response) { double("ThreadResponse", delay_till: Time.now + 1, time_taken: 0.5) }
    
    it "raises error if not waiting for response" do
      expect {
        worker.save_thread_response(response)
      }.to raise_error(/Wasn't waiting for response/)
    end
    
    it "saves response and updates state" do
      worker.instance_variable_set(:@waiting_for_response, true)
      
      worker.save_thread_response(response)
      
      expect(worker.response).to eq(response)
      expect(worker.instance_variable_get(:@waiting_for_response)).to be false
      expect(worker.resume_at).to be >= Time.now
    end
    
    it "uses current time if delay_till is nil" do
      worker.instance_variable_set(:@waiting_for_response, true)
      allow(response).to receive(:delay_till).and_return(nil)
      
      worker.save_thread_response(response)
      
      expect(worker.resume_at).to be_within(0.1).of(Time.now)
    end
    
    it "returns the response for chaining" do
      worker.instance_variable_set(:@waiting_for_response, true)
      
      expect(worker.save_thread_response(response)).to eq(response)
    end
  end
  
  describe "#shutdown" do
    before do
      allow(Fiber).to receive(:current).and_return(main_fiber)
    end
    
    it "closes request queue and sets to nil" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      request_queue = worker.instance_variable_get(:@request_queue)
      
      allow(request_queue).to receive(:close)
      worker.shutdown
      
      expect(request_queue).to have_received(:close)
      expect(worker.instance_variable_get(:@request_queue)).to be_nil
    end
    
    it "joins thread and sets to nil" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      thread = worker.instance_variable_get(:@thread)
      
      allow(thread).to receive(:join)
      worker.shutdown
      
      expect(thread).to have_received(:join)
      expect(worker.instance_variable_get(:@thread)).to be_nil
    end
    
    it "sets resume_at to the future" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      old_resume_at = worker.resume_at
      
      worker.shutdown
      
      expect(worker.resume_at).to be > old_resume_at
    end
    
    it "attempts to resume fiber if it's alive and not the current fiber" do
      alive_fiber = Fiber.new { Fiber.yield }
      worker = described_class.new(alive_fiber, authority, response_queue)
      
      allow(alive_fiber).to receive(:resume)
      allow(alive_fiber).to receive(:object_id).and_return(1234)
      allow(Fiber).to receive(:current).and_return(Fiber.new { :other })
      allow(Fiber.current).to receive(:object_id).and_return(5678)
      
      worker.shutdown
      
      expect(alive_fiber).to have_received(:resume).with(nil)
    end
  end
  
  describe "#resume" do
    before do
      allow(Fiber).to receive(:current).and_return(main_fiber)
    end
    
    let(:worker) { described_class.new(worker_fiber, authority, response_queue) }
    
    it "raises error if fiber is not alive" do
      allow(worker).to receive(:alive?).and_return(false)
      
      expect { worker.resume }.to raise_error(Thread::ClosedQueueError)
    end
    
    it "raises error if no response is available" do
      worker.instance_variable_set(:@response, nil)
      
      expect { worker.resume }.to raise_error(ScraperUtils::Scheduler::OperationWorker::NotReadyError)
    end
    
    it "raises error if called from non-main fiber" do
      allow(Fiber).to receive(:current).and_return(Fiber.new { :wrong_fiber })
      
      expect { worker.resume }.to raise_error(ArgumentError, /Must be run within main fiber/)
    end
    
    it "resumes fiber with response and returns request" do
      test_fiber = Fiber.new { |response|
        expect(response).to eq(:test_response)
        :test_request
      }
      worker = described_class.new(test_fiber, authority, response_queue)
      worker.instance_variable_set(:@response, :test_response)
      
      request = worker.resume
      
      expect(request).to eq(:test_request)
    end
    
    it "submits returned request when non-nil" do
      test_fiber = Fiber.new { |response| :test_request }
      worker = described_class.new(test_fiber, authority, response_queue)
      
      allow(worker).to receive(:submit_request)
      worker.resume
      
      expect(worker).to have_received(:submit_request).with(:test_request)
    end
    
    it "doesn't submit request when nil" do
      test_fiber = Fiber.new { |response| nil }
      worker = described_class.new(test_fiber, authority, response_queue)
      
      allow(worker).to receive(:submit_request)
      worker.resume
      
      expect(worker).not_to have_received(:submit_request)
    end
  end
end
