# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ThreadResponse do
  let(:authority) { :test_authority }
  let(:result) { "test result" }
  let(:error) { nil }
  let(:time_taken) { 0.5 }
  let(:response) { described_class.new(authority, result, error, time_taken) }

  describe "#initialize" do
    it "sets all attributes" do
      expect(response.authority).to eq(authority)
      expect(response.result).to eq(result)
      expect(response.error).to be_nil
      expect(response.time_taken).to eq(time_taken)
      expect(response.delay_till).to be_nil
    end
    
    it "sets authority to nil when not provided" do
      response = described_class.new(nil, result, error, time_taken)
      expect(response.authority).to be_nil
    end
    
    it "works with error argument" do
      error = StandardError.new("Test error")
      response = described_class.new(authority, nil, error, time_taken)
      
      expect(response.error).to eq(error)
    end
  end

  describe "#success?" do
    it "returns true when error is nil" do
      expect(response.success?).to be true
    end
    
    it "returns false when error is present" do
      error = StandardError.new("Test error")
      response = described_class.new(authority, nil, error, time_taken)
      
      expect(response.success?).to be false
    end
  end

  describe "#result!" do
    it "returns result when successful" do
      expect(response.result!).to eq(result)
    end
    
    it "raises error when not successful" do
      error = StandardError.new("Test error")
      response = described_class.new(authority, nil, error, time_taken)
      
      expect { response.result! }.to raise_error(StandardError, "Test error")
    end
  end

  describe "delay_till attribute" do
    it "can be set after initialization" do
      delay_time = Time.now + 5
      response.delay_till = delay_time
      
      expect(response.delay_till).to eq(delay_time)
    end
  end
end
