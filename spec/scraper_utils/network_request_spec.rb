# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../lib/scraper_utils/network_request"

RSpec.describe ScraperUtils::NetworkRequest do
  let(:fiber_id) { 12345 }
  let(:client) { double("client") }
  let(:method) { :get }
  let(:args) { ["https://example.com"] }

  describe "#initialize" do
    it "creates a valid request with all required fields" do
      request = described_class.new(fiber_id, client, method, args)
      expect(request.fiber_id).to eq(fiber_id)
      expect(request.client).to eq(client)
      expect(request.method).to eq(method)
      expect(request.args).to eq(args)
    end

    it "requires a fiber_id" do
      expect {
        described_class.new(nil, client, method, args)
      }.to raise_error(ArgumentError, /Fiber ID must be provided/)
    end

    it "requires a client" do
      expect {
        described_class.new(fiber_id, nil, method, args)
      }.to raise_error(ArgumentError, /Client must be provided/)
    end

    it "requires a method" do
      expect {
        described_class.new(fiber_id, client, nil, args)
      }.to raise_error(ArgumentError, /Method must be provided/)
    end

    it "requires args to be an array" do
      expect {
        described_class.new(fiber_id, client, method, "not an array")
      }.to raise_error(ArgumentError, /Args must be an array/)
    end
  end
end
