# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::OperationWorker do
  let(:response_queue) { Thread::Queue.new }
  let(:authority) { :test_authority }
  let(:main_fiber) { ScraperUtils::Scheduler::Constants::MAIN_FIBER }
  let(:worker_fiber) { Fiber.new { :worker_fiber } }

  describe "#submit_request" do
    let(:worker_fiber_instance) { Fiber.new { Fiber.yield } }
    
    before do
      allow(Fiber).to receive(:current).and_return(main_fiber)
      worker_fiber_instance.resume # Advance to the yield
      allow(Fiber).to receive(:current).and_return(worker_fiber_instance)
    end
    
    let(:worker) { described_class.new(worker_fiber_instance, authority, response_queue) }
    let(:request) { instance_double(ScraperUtils::Scheduler::ThreadRequest) }
    
    it "raises error if already waiting for response" do
      worker.instance_variable_set(:@waiting_for_response, true)
      
      expect { worker.submit_request(request) }.to raise_error(
        ScraperUtils::Scheduler::OperationWorker::NotReadyError, 
        /Cannot make a second request/
      )
    end
    
    it "raises error if request is not a ThreadRequest" do
      expect { worker.submit_request("not a request") }.to raise_error(
        ArgumentError, 
        /Must be passed a valid ThreadRequest/
      )
    end
    
    it "raises error if called from non-worker fiber" do
      allow(Fiber).to receive(:current).and_return(main_fiber)
      
      expect { worker.submit_request(request) }.to raise_error(
        ArgumentError, 
        /Must be run within own fiber/
      )
    end
    
    context "with request queue" do
      before do
        worker.instance_variable_set(:@request_queue, Thread::Queue.new)
      end
      
      it "pushes request to queue and yields with true" do
        request_queue = worker.instance_variable_get(:@request_queue)
        
        allow(request_queue).to receive(:push)
        allow(Fiber).to receive(:yield).and_return(:response_value)
        
        result = worker.submit_request(request)
        
        expect(request_queue).to have_received(:push).with(request)
        expect(worker.instance_variable_get(:@waiting_for_response)).to be true
        expect(result).to eq(:response_value)
      end
      
      it "raises error if response is nil (shutdown signal)" do
        request_queue = worker.instance_variable_get(:@request_queue)
        
        allow(request_queue).to receive(:push)
        allow(Fiber).to receive(:yield).and_return(nil)
        
        expect { worker.submit_request(request) }.to raise_error(/Terminated fiber/)
      end
    end
    
    context "without request queue (parallel disabled)" do
      before do
        worker.instance_variable_set(:@request_queue, nil)
      end
      
      it "executes request directly" do
        thread_response = instance_double(
          ScraperUtils::Scheduler::ThreadResponse, 
          delay_till: nil, 
          time_taken: 0.1
        )
        
        allow(request).to receive(:execute).and_return(thread_response)
        
        result = worker.submit_request(request)
        
        expect(worker.instance_variable_get(:@response)).to eq(thread_response)
        expect(result).to eq(thread_response)
      end
    end
  end
end
