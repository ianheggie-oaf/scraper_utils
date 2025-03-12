# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }
  let(:main_fiber) { ScraperUtils::Scheduler::Constants::MAIN_FIBER }
  let(:worker_fiber) { Fiber.new { :worker_fiber } }

  describe "#initialize" do
    it "creates a valid operation worker" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      
      expect(worker.fiber).to eq(worker_fiber)
      expect(worker.authority).to eq(authority)
      expect(worker.can_resume?).to be true
      expect(worker.response).to be true
      expect(worker.instance_variable_get(:@request_queue)).to be_a(Thread::Queue)
      expect(worker.instance_variable_get(:@thread)).to be_a(Thread)
    end

    it "raises error if fiber or authority is missing" do
      expect { described_class.new(nil, authority, response_queue) }.to raise_error(ArgumentError)
      expect { described_class.new(worker_fiber, nil, response_queue) }.to raise_error(ArgumentError)
    end
    
    it "sets initial state with resume_at in the future" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      
      expect(worker.resume_at).to be >= Time.now - 0.1 # Allow small time variance
      expect(worker.instance_variable_get(:@waiting_for_response)).to be false
    end
    
    it "creates next resume time with small offset" do
      first_time = described_class.next_resume_at
      second_time = described_class.next_resume_at
      
      expect(second_time - first_time).to be_within(0.0001).of(0.001)
    end
  end
  
  describe "#alive?" do
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
    it "returns false if no response is available" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      # Explicitly set response to nil to avoid using the default true
      worker.response = nil
      
      # This test was failing because the implementation may have been returning nil
      # instead of false. We need the exact boolean value.
      expect(worker.can_resume?).to eq(false)
    end
    
    it "returns false if fiber is not alive" do
      dead_fiber = Fiber.new { :done }
      dead_fiber.resume # Exhaust the fiber
      worker = described_class.new(dead_fiber, authority, response_queue)
      
      expect(worker.can_resume?).to eq(false)
    end
    
    it "returns true when response is available and fiber is alive" do
      worker = described_class.new(worker_fiber, authority, response_queue)
      
      expect(worker.can_resume?).to eq(true)
    end
  end
  
  describe "#save_thread_response" do
    let(:worker) { described_class.new(worker_fiber, authority, response_queue) }
    
    it "raises error if not waiting for response" do
      response = ScraperUtils::Scheduler::ThreadResponse.new(
        authority, "test result", nil, 0.5
      )
      
      expect {
        worker.save_thread_response(response)
      }.to raise_error(/Wasn't waiting for response/)
    end
    
    it "saves response and updates state" do
      worker.instance_variable_set(:@waiting_for_response, true)
      response_time = Time.now + 1
      response = ScraperUtils::Scheduler::ThreadResponse.new(
        authority, "test result", nil, 0.5
      )
      response.delay_till = response_time
      
      worker.save_thread_response(response)
      
      expect(worker.response).to eq(response)
      expect(worker.instance_variable_get(:@waiting_for_response)).to be false
      expect(worker.resume_at).to be >= Time.now
    end
    
    it "uses current time if delay_till is nil" do
      worker.instance_variable_set(:@waiting_for_response, true)
      response = ScraperUtils::Scheduler::ThreadResponse.new(
        authority, "test result", nil, 0.5
      )
      
      worker.save_thread_response(response)
      
      expect(worker.resume_at).to be_within(0.1).of(Time.now)
    end
    
    it "returns the response for chaining" do
      worker.instance_variable_set(:@waiting_for_response, true)
      response = ScraperUtils::Scheduler::ThreadResponse.new(
        authority, "test result", nil, 0.5
      )
      
      expect(worker.save_thread_response(response)).to eq(response)
    end
  end
end
