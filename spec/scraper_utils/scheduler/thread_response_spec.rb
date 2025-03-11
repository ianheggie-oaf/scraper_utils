# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ThreadResponse do
  let(:authority) { :test_authority }
  let(:result) { double("Result") }
  let(:error) { nil }
  let(:time_taken) { 0.5 }
  let(:thread_request) { instance_double(ScraperUtils::Scheduler::ThreadRequest, authority: authority) }
  let(:response) { described_class.new(thread_request, result, error, time_taken) }

  describe "#initialize" do
    it "sets required attributes" do
      expect(response.authority).to eq(authority)
      expect(response.result).to eq(result)
      expect(response.error).to eq(error)
      expect(response.time_taken).to be_within(0.0001).of(time_taken)
    end
    
    it "calculates delay_till based on time_taken" do
      # Default behavior is to delay for double the time taken
      expect(response.delay_till).to be_within(0.0001).of(Time.now + 2 * time_taken)
    end
    
    it "sets completed to true" do
      expect(response.completed?).to be true
    end
    
    it "sets failed to false when no error" do
      expect(response.failed?).to be false
    end
    
    it "sets failed to true when error present" do
      response_with_error = described_class.new(
        thread_request, nil, RuntimeError.new("Test error"), time_taken
      )
      
      expect(response_with_error.failed?).to be true
    end
  end
  
  describe "#delay_till=" do
    it "allows custom delay setting" do
      custom_time = Time.now + 10
      response.delay_till = custom_time
      
      expect(response.delay_till).to eq(custom_time)
    end
  end
  
  describe "#inspect" do
    it "includes key attributes in string representation" do
      inspect_output = response.inspect
      
      expect(inspect_output).to include(authority.to_s)
      expect(inspect_output).to include("completed")
      expect(inspect_output).to include(time_taken.to_s)
    end
    
    it "indicates failure when error present" do
      response_with_error = described_class.new(
        thread_request, nil, RuntimeError.new("Test error"), time_taken
      )
      
      inspect_output = response_with_error.inspect
      
      expect(inspect_output).to include("FAILED")
      expect(inspect_output).to include("RuntimeError")
    end
  end
end
