# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::AsyncCommand do
  let(:external_id) { 12345 }
  let(:subject_obj) { double("test_subject") }
  let(:method_name) { :object_id }
  let(:args) { ["https://example.com"] }

  describe "#initialize" do
    it "creates a valid command with all required fields" do
      command = described_class.new(external_id, subject_obj, method_name, args)
      expect(command.external_id).to eq(external_id)
      expect(command.subject).to eq(subject_obj)
      expect(command.method_name).to eq(method_name)
      expect(command.args).to eq(args)
    end

    it "requires an external_id" do
      expect {
        described_class.new(nil, subject_obj, method_name, args)
      }.to raise_error(ArgumentError, /External ID must be provided/)
    end

    it "requires a subject" do
      expect {
        described_class.new(external_id, nil, method_name, args)
      }.to raise_error(ArgumentError, /Subject must be provided/)
    end

    it "requires a valid method" do
      expect {
        described_class.new(external_id, subject_obj, :no_such_method, args)
      }.to raise_error(ArgumentError, /Subject must respond to method/)
    end

    it "requires a method" do
      expect {
        described_class.new(external_id, subject_obj, nil, args)
      }.to raise_error(ArgumentError, /Method name must be provided/)
    end


    it "requires args to be an array" do
      expect {
        described_class.new(external_id, subject_obj, method_name, "not an array")
      }.to raise_error(ArgumentError, /Args must be an array/)
    end
    
    it "accepts various types as external_id" do
      expect {
        described_class.new("string_id", subject_obj, method_name, args)
        described_class.new(:symbol_id, subject_obj, method_name, args)
        described_class.new(12345, subject_obj, method_name, args)
        described_class.new(Object.new, subject_obj, method_name, args)
      }.not_to raise_error
    end

    it "executes a simple sleep and returns the response" do
      command = ScraperUtils::AsyncCommand.new(external_id, Kernel, :sleep, [0.001])

      # Queue the request
      response = command.execute

      # Check that we got a response
      expect(response).to be_a(ScraperUtils::AsyncResponse)
      expect(response.external_id).to eq(external_id)
      expect(response.result).to be_a(Integer)
      expect(response.error).to be_nil
      expect(response.time_taken).to be > 0
      expect(response.success?).to be true
      expect(response.result).to be 0
    end
  end
end
