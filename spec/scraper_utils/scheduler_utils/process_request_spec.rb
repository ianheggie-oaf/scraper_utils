# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ProcessRequest do
  let(:authority) { :test_authority }
  let(:subject_obj) { double("test_subject") }
  let(:method_name) { :object_id }
  let(:args) { ["https://example.com"] }

  describe "#initialize" do
    it "creates a valid command with all required fields" do
      command = described_class.new(authority, subject_obj, method_name, args)
      expect(command.authority).to eq(authority)
      expect(command.subject).to eq(subject_obj)
      expect(command.method_name).to eq(method_name)
      expect(command.args).to eq(args)
    end

    it "does not require an authority" do
      described_class.new(nil, subject_obj, method_name, args)
    end

    it "requires a subject" do
      expect {
        described_class.new(authority, nil, method_name, args)
      }.to raise_error(ArgumentError, /Subject must be provided/)
    end

    it "requires a valid method" do
      expect {
        described_class.new(authority, subject_obj, :no_such_method, args)
      }.to raise_error(ArgumentError, /Subject must respond to method/)
    end

    it "requires a method" do
      expect {
        described_class.new(authority, subject_obj, nil, args)
      }.to raise_error(ArgumentError, /Method name must be provided/)
    end

    it "requires args to be an array" do
      expect {
        described_class.new(authority, subject_obj, method_name, "not an array")
      }.to raise_error(ArgumentError, /Args must be an array/)
    end

    it "executes a simple sleep and returns the response" do
      command = ScraperUtils::Scheduler::ProcessRequest.new(authority, Kernel, :sleep, [0.001])

      # Queue the request
      response = command.execute

      # Check that we got a response
      expect(response).to be_a(ScraperUtils::Scheduler::ThreadResponse)
      expect(response.authority).to eq(authority)
      expect(response.result).to be_a(Integer)
      expect(response.error).to be_nil
      expect(response.time_taken).to be > 0
      expect(response.success?).to be true
      expect(response.result).to be 0
    end
  end
end
