# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ProcessRequest do
  let(:authority) { :test_authority }
  let(:subject_instance) { Kernel } # Real object everyone has access to
  let(:method_name) { :sleep }
  let(:args) { [0.001] } # Very small value to keep tests fast
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
      # Create a test class with a method we can track
      test_class = Class.new do
        attr_reader :called_with
        
        def test_method(*args)
          @called_with = args
          "result value"
        end
      end
      
      test_instance = test_class.new
      test_request = described_class.new(authority, test_instance, :test_method, [1, 2, 3])
      
      response = test_request.execute
      
      expect(test_instance.called_with).to eq([1, 2, 3])
      expect(response.result).to eq("result value")
      expect(response.error).to be_nil
      expect(response.success?).to be true
    end
    
    it "captures exceptions during execution" do
      # Create a test class that raises an error
      test_class = Class.new do
        def error_method
          raise "Test error"
        end
      end
      
      test_instance = test_class.new
      test_request = described_class.new(authority, test_instance, :error_method, [])
      
      response = test_request.execute
      
      expect(response.result).to be_nil
      expect(response.error).to be_a(RuntimeError)
      expect(response.error.message).to eq("Test error")
      expect(response.success?).to be false
    end
    
    it "tracks execution time" do
      # Use sleep for predictable timing
      test_request = described_class.new(authority, Kernel, :sleep, [0.01])
      
      response = test_request.execute
      
      expect(response.time_taken).to be > 0
      expect(response.time_taken).to be_within(0.05).of(0.01) # Allow some overhead
    end
    
    it "adds delay_till from subject when present" do
      # Create a test class with @delay_till
      test_class = Class.new do
        attr_reader :delay_till
        
        def initialize
          @delay_till = Time.now + 10
        end
        
        def test_method
          "test"
        end
      end
      
      test_instance = test_class.new
      test_request = described_class.new(authority, test_instance, :test_method, [])
      
      response = test_request.execute
      
      expect(response.delay_till).to eq(test_instance.delay_till)
    end
  end
end
