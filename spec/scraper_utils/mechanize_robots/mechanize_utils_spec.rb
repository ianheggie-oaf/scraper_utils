# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::MechanizeUtils do
  describe ".mechanize_agent" do
    let(:page_content) { "<html><body>Test page</body></html>" }

    before do
      stub_request(:get, "https://example.com")
        .to_return(status: 200, body: page_content)
    end

    context "with robots.txt" do
      before do
        stub_request(:get, "https://example.com/robots.txt")
          .to_return(status: 200, body: <<~ROBOTS
            User-agent: ScraperUtils
            Disallow: /private
          ROBOTS
          )
      end

      it "respects robots.txt Disallow by default (compliant mode on)" do
        stub_request(:get, "https://example.com/private")
          .to_return(status: 200, body: page_content)

        agent = described_class.mechanize_agent
        expect { agent.get("https://example.com/private") }
          .to raise_error(ScraperUtils::UnprocessableSite)
      end

      it "ignores robots.txt when compliant mode is explicitly set to false" do
        stub_request(:get, "https://example.com/private")
          .to_return(status: 200, body: page_content)

        agent = described_class.mechanize_agent(compliant_mode: false)
        expect { agent.get("https://example.com/private") }.not_to raise_error
      end
    end
  end
end
