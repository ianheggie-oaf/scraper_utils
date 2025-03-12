# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ThreadRequest do
  let(:authority) { :test_authority }
  let(:request) { described_class.new(authority) }

  describe "#initialize" do
    it "sets required attributes" do
      expect(request.authority).to eq(authority)
    end
  end
  
  describe "#execute" do
    it "raises NotImplementedError" do
      expect { request.execute }.to raise_error(NotImplementedError, /Implement in subclass/)
    end
  end
  
  describe "#execute_block" do
    it "calls block and returns ThreadResponse with result" do
      # Use real Time objects, but freeze time for consistent testing
      start_time = Time.now
      end_time = start_time + 0.7
      
      allow(Time).to receive(:now).and_return(start_time, end_time)
      
      response = request.execute_block { "real result" }
      
      expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
      expect(response.authority).to eq(authority)
      expect(response.result).to eq("real result")
      expect(response.error).to be_nil
      expect(response.time_taken).to be_within(0.0001).of(0.7)
    end
    
    it "captures exceptions during block execution" do
      test_error = RuntimeError.new("Test error")
      
      response = request.execute_block { raise test_error }
      
      expect(response.result).to be_nil
      expect(response.error).to eq(test_error)
      expect(response.success?).to be false
    end
    
    it "measures actual execution time" do
      # Use sleep for real timing measurement
      response = request.execute_block { sleep(0.01); "result" }
      
      expect(response.time_taken).to be > 0
      expect(response.time_taken).to be_within(0.05).of(0.01) # Allow some overhead
    end
  end
end
