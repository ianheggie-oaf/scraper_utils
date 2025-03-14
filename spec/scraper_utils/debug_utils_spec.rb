# frozen_string_literal: true

require_relative "../spec_helper"
require "mechanize"

RSpec.describe ScraperUtils::DebugUtils do
  describe ".debug?" do
    context "when DEBUG environment variable is set" do
      before { ENV[ScraperUtils::DebugUtils::DEBUG_ENV_VAR] = "3" }
      after { ENV.delete(ScraperUtils::DebugUtils::DEBUG_ENV_VAR) }

      it "returns true" do
        expect(described_class.debug?).to be true
      end
    end

    context "when DEBUG environment variable is not set" do
      before { ENV.delete(ScraperUtils::DebugUtils::DEBUG_ENV_VAR) }

      it "returns false" do
        expect(described_class.debug?).to be false
      end
    end

    context "when MORPH_DEBUG environment variable is set" do
      before { ENV[ScraperUtils::DebugUtils::MORPH_DEBUG_ENV_VAR] = "3" }
      after { ENV.delete(ScraperUtils::DebugUtils::MORPH_DEBUG_ENV_VAR) }

      it "returns true" do
        expect(described_class.debug?).to be true
      end
    end

    context "when MORPH_DEBUG environment variable is not set" do
      before { ENV.delete(ScraperUtils::DebugUtils::MORPH_DEBUG_ENV_VAR) }

      it "returns false" do
        expect(described_class.debug?).to be false
      end
    end
  end

  describe ".debug_request" do
    let(:http_method) { "GET" }
    let(:url) { "https://example.com" }

    context "when debug mode is on" do
      before { allow(described_class).to receive(:basic?).and_return(true) }

      it "prints request details" do
        expect do
          described_class.debug_request(http_method, url, parameters: { key: "value" })
        end.to output(%r{GET https://example.com}).to_stdout
      end

      it "prints parameters" do
        expect do
          described_class.debug_request(http_method, url, parameters: { key: "value" })
        end.to output(/Parameters:/).to_stdout
      end

      it "prints headers" do
        expect do
          described_class.debug_request(http_method, url,
                                        headers: { "Content-Type": "application/json" })
        end.to output(/Headers:/).to_stdout
      end

      it "prints body" do
        expect do
          described_class.debug_request(http_method, url, body: { data: "test" })
        end.to output(/Body:/).to_stdout
      end
    end

    context "when debug mode is off" do
      before { allow(described_class).to receive(:basic?).and_return(false) }

      it "does not print anything" do
        expect do
          described_class.debug_request(http_method, url)
        end.not_to output.to_stdout
      end
    end
  end

  describe ".debug_page" do
    before do
      stub_request(:get, "https://example.com/test")
        .to_return(
          body: "<html><title>Test Page</title><body>Test Content</body></html>",
          headers: {'Content-Type' => 'text/html'}
        )
    end
    
    let(:agent) { Mechanize.new }
    let(:page) { agent.get("https://example.com/test") }
    let(:message) { "Test debug page" }

    context "when debug mode is on" do
      before { allow(described_class).to receive(:trace?).and_return(true) }

      it "prints page details" do
        expect do
          described_class.debug_page(page, message)
        end.to output(/DEBUG: Test debug page/).to_stdout
      end

      it "prints page title and URI" do
        expect do
          described_class.debug_page(page, message)
        end.to output(/Current URL: https:\/\/example.com\/test/).to_stdout
        
        expect do
          described_class.debug_page(page, message)
        end.to output(/Page title: Test Page/).to_stdout
      end
    end

    context "when page has no title" do
      before do
        stub_request(:get, "https://example.com/no-title")
          .to_return(
            body: "<html><body>No Title Content</body></html>",
            headers: {'Content-Type' => 'text/html'}
          )
        
        allow(described_class).to receive(:trace?).and_return(true)
      end
      
      let(:no_title_page) { agent.get("https://example.com/no-title") }

      it "handles missing title gracefully" do
        expect do
          described_class.debug_page(no_title_page, message)
        end.to output(/Current URL: https:\/\/example.com\/no-title/).to_stdout
        
        # Should not output page title section
        expect do
          described_class.debug_page(no_title_page, message)
        end.not_to output(/Page title:/).to_stdout
      end
    end

    context "when debug mode is off" do
      before { allow(described_class).to receive(:trace?).and_return(false) }

      it "does not print anything" do
        expect do
          described_class.debug_page(page, message)
        end.not_to output.to_stdout
      end
    end
  end

  describe ".debug_selector" do
    before do
      stub_request(:get, "https://example.com/elements")
        .to_return(
          body: "<html><body><div class='test'>Test Element</div></body></html>",
          headers: {'Content-Type' => 'text/html'}
        )
    end
    
    let(:agent) { Mechanize.new }
    let(:page) { agent.get("https://example.com/elements") }
    let(:selector) { "div.test" }
    let(:message) { "Test selector" }

    context "when debug mode is on" do
      before { allow(described_class).to receive(:trace?).and_return(true) }

      it "prints selector details when element found" do
        expect do
          described_class.debug_selector(page, selector, message)
        end.to output(/DEBUG: Test selector/).to_stdout
        
        expect do
          described_class.debug_selector(page, selector, message)
        end.to output(/Looking for selector: div.test/).to_stdout
        
        expect do
          described_class.debug_selector(page, selector, message)
        end.to output(/Found element:/).to_stdout
      end

      it "prints page body when element not found" do
        expect do
          described_class.debug_selector(page, "div.not-found", message)
        end.to output(/Element not found/).to_stdout
      end
    end

    context "when debug mode is off" do
      before { allow(described_class).to receive(:trace?).and_return(false) }

      it "does not print anything" do
        expect do
          described_class.debug_selector(page, selector, message)
        end.not_to output.to_stdout
      end
    end
  end
end
