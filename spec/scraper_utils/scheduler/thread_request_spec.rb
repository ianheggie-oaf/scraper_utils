# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ThreadRequest do
  let(:authority) { :test_authority }
  let(:request) { described_class.new(authority) }

  describe "#initialize" do
    it "sets authority attribute" do
      expect(request.authority).to eq(authority)
    end
    
    it "works with nil authority" do
      request = described_class.new(nil)
      expect(request.authority).to be_nil
    end
  end

  describe "#execute" do
    it "raises NotImplementedError" do
      expect { request.execute }.to raise_error(NotImplementedError, /Implement in subclass/)
    end
  end

  describe "#execute_block" do
    it "captures successful result with timing" do
      allow(Time).to receive(:now).and_return(100, 100.5) # Mock 0.5s execution time
      
      result = request.execute_block do
        "success result"
      end
      
      expect(result).to be_a(ScraperUtils::Scheduler::ThreadResponse)
      expect(result.authority).to eq(authority)
      expect(result.result).to eq("success result")
      expect(result.error).to be_nil
      expect(result.time_taken).to eq(0.5)
    end
    
    it "captures error with timing" do
      test_error = StandardError.new("Test error")
      allow(Time).to receive(:now).and_return(100, 100.7) # Mock 0.7s execution time
      
      result = request.execute_block do
        raise test_error
      end
      
      expect(result).to be_a(ScraperUtils::Scheduler::ThreadResponse)
      expect(result.authority).to eq(authority)
      expect(result.result).to be_nil
      expect(result.error).to eq(test_error)
      expect(result.time_taken).to be_within(0.001).of(0.7)
    end
  end
end
