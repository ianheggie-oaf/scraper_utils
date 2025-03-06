# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../lib/scraper_utils/network_response"

RSpec.describe ScraperUtils::NetworkResponse do
  let(:fiber_id) { 12345 }
  let(:result) { "response result" }
  let(:error) { nil }
  let(:time_taken) { 0.5 }

  describe "#initialize" do
    it "creates a response with all fields" do
      response = described_class.new(fiber_id, result, error, time_taken)
      expect(response.fiber_id).to eq(fiber_id)
      expect(response.result).to eq(result)
      expect(response.error).to eq(error)
      expect(response.time_taken).to eq(time_taken)
    end

    it "sets default values for optional parameters" do
      response = described_class.new(fiber_id, result)
      expect(response.error).to be_nil
      expect(response.time_taken).to eq(0)
    end
  end

  describe "#success?" do
    it "returns true when there is no error" do
      response = described_class.new(fiber_id, result)
      expect(response.success?).to be true
    end

    it "returns false when there is an error" do
      error = StandardError.new("test error")
      response = described_class.new(fiber_id, nil, error)
      expect(response.success?).to be false
    end
  end
end
