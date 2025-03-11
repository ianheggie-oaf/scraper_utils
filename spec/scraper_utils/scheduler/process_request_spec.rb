# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ProcessRequest do
  let(:authority) { :test_authority }
  let(:subject) { double("MechanizeClient", get: "<html></html>") }
  let(:method_name) { :get }
  let(:args) { ["https://example.com"] }
  let(:request) { described_class.new(authority, subject, method_name, args) }

  describe "#initialize" do
    it "sets required attributes" do
      expect(request.authority).to eq(authority)
      expect(request.instance_variable_get(:@subject)).to eq(subject)
      expect(request.instance_variable_get(:@method_name)).to eq(method_name)
      expect(request.instance_variable_get(:@args)).to eq(args)
    end
    
    it "raises error if subject is missing" do
      expect { 
        described_class.new(authority, nil, method_name, args) 
      }.to raise_error(ArgumentError, /Subject must be provided/)
    end
    
    it "raises error if method_name is missing" do
      expect { 
        described_class.new(authority, subject, nil, args)
      }.to raise_error(ArgumentError, /Method name must be provided/)
    end
    
    it "raises error if args is not an array" do
      expect { 
        described_class.new(authority, subject, method_name, "not an array")
      }.to raise_error(ArgumentError, /Args must be an array/)
    end
  end

  describe "#execute" do
    it "calls method on subject with args" do
      result = double("Result")
      allow(subject).to receive(method_name).with(*args).and_return(result)
      
      response = request.execute
      
      expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
      expect(response.authority).to eq(authority)
      expect(response.result).to eq(result)
      expect(response.error).to be_nil
    end
    
    it "captures error if method raises" do
      test_error = StandardError.new("Test error")
      allow(subject).to receive(method_name).with(*args).and_raise(test_error)
      
      response = request.execute
      
      expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
      expect(response.authority).to eq(authority)
      expect(response.result).to be_nil
      expect(response.error).to eq(test_error)
    end
    
    it "delegates execution to execute_block" do
      allow(subject).to receive(method_name)
      
      request.execute
      
      expect(subject).to have_received(method_name).with(*args)
    end
  end
end
