# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ThreadRequest do
  let(:authority) { :test_authority }
  let(:processing_block) { -> { :result } }
  let(:request) { described_class.new(authority, &processing_block) }

  describe "#initialize" do
    it "sets required attributes" do
      expect(request.authority).to eq(authority)
      expect(request.instance_variable_get(:@block)).to eq(processing_block)
    end
    
    it "raises error if authority is missing" do
      expect { 
        described_class.new(nil, &processing_block) 
      }.to raise_error(ArgumentError, /Authority must be provided/)
    end
    
    it "raises error if block is missing" do
      expect { 
        described_class.new(authority) 
      }.to raise_error(ArgumentError, /Block must be provided/)
    end
  end
  
  describe "#execute" do
    it "calls block and returns ThreadResponse with result" do
      start_time = Time.now
      allow(Time).to receive(:now).and_return(start_time, start_time + 0.7)
      
      response = request.execute
      
      expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
      expect(response.authority).to eq(authority)
      expect(response.result).to eq(:result)
      expect(response.error).to be_nil
      expect(response.time_taken).to be_within(0.0001).of(0.7)
    end
    
    it "captures exceptions during block execution" do
      test_error = RuntimeError.new("Test error")
      error_block = -> { raise test_error }
      error_request = described_class.new(authority, &error_block)
      
      response = error_request.execute
      
      expect(response.result).to be_nil
      expect(response.error).to eq(test_error)
      expect(response.failed?).to be true
    end
  end
end
