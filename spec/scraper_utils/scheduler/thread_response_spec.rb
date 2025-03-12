# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ThreadResponse do
  let(:authority) { :test_authority }
  let(:result) { "test_result" }
  let(:error) { nil }
  let(:time_taken) { 0.5 }
  let(:response) { described_class.new(authority, result, error, time_taken) }

  describe "#initialize" do
    it "sets required attributes" do
      expect(response.authority).to eq(authority)
      expect(response.result).to eq(result)
      expect(response.error).to eq(error)
      expect(response.time_taken).to be_within(0.0001).of(time_taken)
    end
    
    it "initializes delay_till to nil" do
      expect(response.delay_till).to be_nil
    end
  end
  
  describe "#success?" do
    it "returns true when there is no error" do
      expect(response.success?).to be true
    end
    
    it "returns false when there is an error" do
      test_error = RuntimeError.new("Test error")
      response_with_error = described_class.new(
        authority, nil, test_error, time_taken
      )
      expect(response_with_error.success?).to be false
    end
  end
  
  describe "#delay_till=" do
    it "allows custom delay setting" do
      custom_time = Time.now + 10
      response.delay_till = custom_time
      
      expect(response.delay_till).to eq(custom_time)
    end
  end
  
  describe "#result!" do
    it "returns result when success" do
      expect(response.result!).to eq(result)
    end
    
    it "raises error when not success" do
      test_error = RuntimeError.new("Test error")
      error_response = described_class.new(
        authority, nil, test_error, time_taken
      )
      
      expect { error_response.result! }.to raise_error(test_error)
    end
  end
  
  describe "#inspect" do
    it "includes key attributes in string representation" do
      inspect_output = response.inspect
      
      expect(inspect_output).to include(authority.to_s)
      expect(inspect_output).to include("success")
      expect(inspect_output).to include(time_taken.to_s)
    end
    
    it "indicates failure when error present" do
      test_error = RuntimeError.new("Test error")
      response_with_error = described_class.new(
        authority, nil, test_error, time_taken
      )
      
      inspect_output = response_with_error.inspect
      
      expect(inspect_output).to include("FAILED")
      expect(inspect_output).to include("RuntimeError")
    end
  end
end
