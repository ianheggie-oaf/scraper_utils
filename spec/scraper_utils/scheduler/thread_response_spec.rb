# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler::ThreadResponse do
  let(:authority) { :test_authority }
  let(:response_type) { :response_type }
  let(:result) { "response result" }
  let(:no_error) { nil }
  let(:time_taken) { 0.5 }

  describe "#initialize" do
    it "creates a response with all fields" do
      response = described_class.new(authority, response_type, result, no_error, time_taken)
      expect(response.authority).to eq(authority)
      expect(response.result).to eq(result)
      expect(response.error).to eq(no_error)
      expect(response.time_taken).to eq(time_taken)
    end
  end

  describe "#success?" do
    it "returns true when there is no error" do
      response = described_class.new(authority, response_type, result, no_error, time_taken)

      expect(response.success?).to be true
    end

    it "returns false when there is an error" do
      an_error = StandardError.new("test error")
      response = described_class.new(authority, response_type, result, an_error, time_taken)
      expect(response.success?).to be false
    end
  end
end
