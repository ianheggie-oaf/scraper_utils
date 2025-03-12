# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ProcessRequest do
  let(:authority) { :test_authority }
  let(:subject_instance) { double("MechanizeClient", get: "<html></html>") }
  let(:method_name) { :get }
  let(:args) { ["https://example.com"] }
  let(:request) { described_class.new(authority, subject_instance, method_name, args) }

  describe "#initialize" do
    it "creates a valid command with all required fields" do
      expect(request.authority).to eq(authority)
      expect(request.subject).to eq(subject_instance)
      expect(request.method_name).to eq(method_name)
      expect(request.args).to eq(args)
    end
    
    it "does not require an authority" do
      expect {
        described_class.new(nil, subject_instance, method_name, args)
      }.not_to raise_error
    end
    
    it "requires a subject" do
      expect {
        described_class.new(authority, nil, method_name, args)
      }.to raise_error(ArgumentError, /Subject must be provided/)
    end
    
    it "requires a valid method" do
      expect {
        described_class.new(authority, subject_instance, :invalid_method, args)
      }.to raise_error(ArgumentError, /Subject must respond to method/)
    end
    
    it "requires a method" do
      expect {
        described_class.new(authority, subject_instance, nil, args)
      }.to raise_error(ArgumentError, /Method name must be provided/)
    end
    
    it "requires args to be an array" do
      expect {
        described_class.new(authority, subject_instance, method_name, "not an array")
      }.to raise_error(ArgumentError, /Args must be an array/)
    end
  end
  
  describe "#execute" do
    it "calls method on subject with args" do
      result = double("Result")
      allow(subject_instance).to receive(method_name).with(*args).and_return(result)
      
      response = request.execute
      
      expect(response.result).to eq(result)
      expect(response.error).to be_nil
      expect(response.success?).to be true
    end
    
    it "captures exceptions during execution" do
      test_error = RuntimeError.new("Test error")
      allow(subject_instance).to receive(method_name).and_raise(test_error)
      
      response = request.execute
      
      expect(response.result).to be_nil
      expect(response.error).to eq(test_error)
      expect(response.success?).to be false
    end
    
    it "tracks execution time" do
      start_time = Time.now
      allow(Time).to receive(:now).and_return(start_time, start_time + 0.7)
      
      response = request.execute
      
      expect(response.time_taken).to be_within(0.0001).of(0.7)
    end
    
    it "adds delay_till from subject when present" do
      future_time = Time.now + 10
      allow(subject_instance).to receive(:instance_variable_get).with(:@delay_till).and_return(future_time)
      
      response = request.execute
      
      expect(response.delay_till).to eq(future_time)
    end
  end
end
