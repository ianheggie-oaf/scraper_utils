# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../lib/scraper_utils/fiber_scheduler"

RSpec.describe ScraperUtils::FiberScheduler do
  before do
    described_class.reset!
  end

  describe ".register_operation" do
    it "creates a fiber and adds it to the registry" do
      expect do
        described_class.register_operation("test_authority") { :does_nothing }
      end.to change { described_class.registry.size }.by(1)
    end

    it "automatically enables fiber scheduling" do
      expect(described_class.enabled?).to be false
      described_class.register_operation("test_authority") { :does_nothing }
      expect(described_class.enabled?).to be true
    end

    it "creates a fiber state for the fiber" do
      fiber = described_class.register_operation("test_authority") { :does_nothing }
      expect(described_class.fiber_states).to have_key(fiber.object_id)
      
      state = described_class.fiber_states[fiber.object_id]
      expect(state).to be_a(ScraperUtils::FiberState)
      expect(state.authority).to eq("test_authority")
    end

    it "executes the given block in a fiber" do
      block_executed = false
      fiber = described_class.register_operation("test_authority") do
        block_executed = true
      end
      fiber.resume
      expect(block_executed).to be true
    end

    it "captures exceptions and stores them by authority" do
      fiber = described_class.register_operation("error_authority") do
        raise "Test error"
      end
      fiber.resume
      expect(described_class.exceptions).to have_key("error_authority")
      expect(described_class.exceptions["error_authority"].message).to eq("Test error")
    end

    it "cleans up after fiber completion" do
      fiber = described_class.register_operation("test_authority") { :does_nothing }
      expect(described_class.registry).to include(fiber)
      expect(described_class.fiber_states).to have_key(fiber.object_id)
      
      fiber.resume
      
      expect(described_class.registry).to be_empty
      expect(described_class.fiber_states).not_to have_key(fiber.object_id)
    end

    it "cleans up after exception" do
      fiber = described_class.register_operation("error_authority") do
        raise "Test error"
      end
      fiber.resume
      expect(described_class.registry).to be_empty
      expect(described_class.fiber_states).not_to have_key(fiber.object_id)
    end
  end

  describe ".current_authority" do
    it "returns the authority for the current fiber" do
      executed = false
      fiber = described_class.register_operation("test_authority") do
        executed = (described_class.current_authority == "test_authority")
      end
      fiber.resume
      expect(executed).to be true
    end

    it "returns nil when not in a fiber" do
      expect(described_class.current_authority).to be_nil
    end
  end

  describe ".queue_network_request" do
    let(:command_args) { [double("client"), :get, ["https://example.com"]] }
    
    it "marks the fiber as waiting for response" do
      executed = false
      fiber = described_class.register_operation("test_authority") do
        # Setup for test
        state = described_class.fiber_states[Fiber.current.object_id]
        expect(state.waiting_for_response?).to be false
        
        # Mock ThreadScheduler to avoid actual execution
        thread_scheduler = double("thread_scheduler")
        allow(described_class).to receive(:thread_scheduler).and_return(thread_scheduler)
        allow(thread_scheduler).to receive(:queue_request)
        
        # Call the method being tested but set up to not actually yield
        # to avoid losing control of the test
        allow(Fiber).to receive(:yield)
        
        described_class.queue_network_request(*command_args)
        
        # Verify state was updated
        executed = state.waiting_for_response?
      end
      
      fiber.resume
      expect(executed).to be true
    end

    it "queues the request with the thread scheduler" do
      thread_scheduler = double("thread_scheduler")
      allow(described_class).to receive(:thread_scheduler).and_return(thread_scheduler)
      
      executed = false
      fiber = described_class.register_operation("test_authority") do
        # Expect queue_request to be called with correct arguments
        expect(thread_scheduler).to receive(:queue_request) do |request|
          # Verify it's a proper NetworkRequest
          expect(request).to be_a(ScraperUtils::NetworkRequest)
          expect(request.fiber_id).to eq(Fiber.current.object_id)
          expect(request.client).to eq(command_args[0])
          expect(request.method).to eq(command_args[1])
          expect(request.args).to eq(command_args[2])
          executed = true
        end
        
        # Don't actually yield to avoid losing control
        allow(Fiber).to receive(:yield)
        
        described_class.queue_network_request(*command_args)
      end
      
      fiber.resume
      expect(executed).to be true
    end
    
    it "returns the response when resumed" do
      thread_scheduler = double("thread_scheduler")
      allow(described_class).to receive(:thread_scheduler).and_return(thread_scheduler)
      allow(thread_scheduler).to receive(:queue_request)
      
      test_result = "test response"
      
      fiber = described_class.register_operation("test_authority") do
        # Start a fake request
        result_promise = described_class.queue_network_request(*command_args)
        
        # The scheduler would normally set this after processing responses
        fiber_id = Fiber.current.object_id
        state = described_class.fiber_states[fiber_id]
        state.response = test_result
        state.waiting_for_response = false
        
        # Continue with mock "resume" to return the result
        result_promise
      end
      
      # Custom yield behavior to simulate resuming after response
      allow_any_instance_of(Fiber).to receive(:yield) do
        # This simulates what would happen in run_all when response is ready
        fiber.resume
      end
      
      result = fiber.resume
      expect(result).to eq(test_result)
    end
  end

  describe ".run_all" do
    it "runs all registered fibers to completion" do
      results = []
      described_class.register_operation("auth1") { results << "auth1" }
      described_class.register_operation("auth2") { results << "auth2" }

      described_class.run_all

      expect(results).to contain_exactly("auth1", "auth2")
      expect(described_class.registry).to be_empty
      expect(described_class.fiber_states).to be_empty
    end

    it "returns exceptions encountered during execution" do
      described_class.register_operation("auth1") { raise "Error 1" }
      described_class.register_operation("auth2") { raise "Error 2" }

      exceptions = described_class.run_all

      expect(exceptions.keys).to contain_exactly("auth1", "auth2")
      expect(exceptions["auth1"].message).to eq("Error 1")
      expect(exceptions["auth2"].message).to eq("Error 2")
    end
    
    it "processes thread responses before checking for ready fibers" do
      # This test is complex and would require significant setup to properly
      # test the integration between ThreadScheduler and FiberScheduler
      # 
      # We'll skip this for now, but should implement it when implementing
      # the actual integration
      pending "Complex integration test to be implemented"
    end
  end
end
