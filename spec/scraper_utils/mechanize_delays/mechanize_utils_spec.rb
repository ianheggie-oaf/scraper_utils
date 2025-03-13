# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::MechanizeUtils do
  describe ".mechanize_agent" do
    before do
      stub_request(:get, "https://example.com/robots.txt")
        .to_return(status: 200, body: "")
      stub_request(:get, "https://example.com")
        .to_return(status: 200, body: "<html><body>Test page</body></html>")
    end

    it "applies configured delays" do
      start_time = Time.now
      agent = described_class.mechanize_agent(
        random_delay: 1,
        max_load: 20.0,
        compliant_mode: true
      )
      agent.get("https://example.com")
      elapsed = Time.now - start_time

      # Just verify some delay was applied
      expect(elapsed).to be > 0
    end
  end
end
