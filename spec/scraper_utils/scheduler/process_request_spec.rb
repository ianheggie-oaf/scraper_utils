# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ProcessRequest do
  let(:authority) { :test_authority }
  let(:subject_instance) { double("MechanizeClient", get: "<html></html>") }
  let(:method_name) { :get }
  let(:args) { ["https://example.com"] }
  let(:request) { described_class.new(authority, subject_instance, method_name, args) }

  describe "#initialize" do
    it "sets required attributes" do
      expect(request.authority).to eq(authority)
      expect(request.instance_variable_get(:@subject)).to eq(subject_instance)
      expect(request.instance_variable_get(:@method_name)).to eq(method_name)
      expect(request.instance_variable_get(:@args)).to eq(args)
    end
    
    it "raises error if authority is missing" do
      expect { 
        described_class.new(nil, subject_instance, method_name, args) 
      }.to raise_error(ArgumentError, /Authority must be provided/)
    end
    
    it "raises error if subject is missing" do
      expect { 
        described_class.new(authority, nil, method_name, args) 
      }.to raise_error(ArgumentError, /Subject must be provided/)
    end
    
    it "raises error if method_name is missing" do
      expect { 
        described_class.new(authority, subject_instance, nil, args) 
      }.to raise_error(ArgumentError, /Method name must be provided/)
    end
  end
  
  describe "#execute" do
    it "calls method on subject with args" do
      result = double("Result")
      allow(subject_instance).to receive(method_name).with(*args).and_return(result)
      
      response = request.execute
      
      expect(response.result).to eq(result)
      expect(response.error).to be_nil
      expect(response.completed?).to be true
      expect(response.failed?).to be false
    end
    
    it "captures exceptions during execution" do
      test_error = RuntimeError.new("Test error")
      allow(subject_instance).to receive(method_name).and_raise(test_error)
      
      response = request.execute
      
      expect(response.result).to be_nil
      expect(response.error).to eq(test_error)
      expect(response.completed?).to be true
      expect(response.failed?).to be true
    end
    
    it "tracks execution time" do
      start_time = Time.now
      allow(Time).to receive(:now).and_return(start_time, start_time + 0.7)
      
      response = request.execute
      
      expect(response.time_taken).to be_within(0.0001).of(0.7)
    end
  end
end
