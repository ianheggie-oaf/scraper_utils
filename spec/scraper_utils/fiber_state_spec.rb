# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../lib/scraper_utils/fiber_state"

RSpec.describe ScraperUtils::FiberState do
  let(:fiber_id) { 12345 }
  let(:authority) { "test_authority" }
  let(:state) { described_class.new(fiber_id, authority) }

  describe "#initialize" do
    it "sets the fiber_id and authority" do
      expect(state.fiber_id).to eq(fiber_id)
      expect(state.authority).to eq(authority)
    end

    it "initializes with default values" do
      expect(state.resume_at).to be_nil
      expect(state.waiting_for_response?).to be false
      expect(state.response).to be_nil
      expect(state.error).to be_nil
    end
  end

  describe "#waiting_for_response?" do
    it "returns the waiting state" do
      expect(state.waiting_for_response?).to be false
      state.waiting_for_response = true
      expect(state.waiting_for_response?).to be true
    end
  end

  describe "#response_ready?" do
    it "returns true when response is present and not waiting" do
      state.response = "response"
      state.waiting_for_response = false
      expect(state.response_ready?).to be true
    end

    it "returns false when waiting for response" do
      state.response = "response"
      state.waiting_for_response = true
      expect(state.response_ready?).to be false
    end

    it "returns false when response is nil" do
      state.response = nil
      state.waiting_for_response = false
      expect(state.response_ready?).to be false
    end
  end

  describe "#ready_to_run?" do
    let(:current_time) { Time.now }
    
    it "returns true when response is ready" do
      allow(state).to receive(:response_ready?).and_return(true)
      expect(state.ready_to_run?(current_time)).to be true
    end

    it "returns true when resume_at time has passed" do
      state.resume_at = current_time - 1
      allow(state).to receive(:response_ready?).and_return(false)
      expect(state.ready_to_run?(current_time)).to be true
    end

    it "returns false when not response ready and resume time is in future" do
      state.resume_at = current_time + 1
      allow(state).to receive(:response_ready?).and_return(false)
      expect(state.ready_to_run?(current_time)).to be false
    end
  end
end
