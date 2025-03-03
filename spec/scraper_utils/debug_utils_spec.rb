# frozen_string_literal: true

require_relative "../spec_helper"
require "json"

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
  end

  describe ".debug_request" do
    let(:method) { "GET" }
    let(:url) { "https://example.com" }

    context "when debug mode is on" do
      before { allow(described_class).to receive(:debug?).and_return(true) }

      it "prints request details" do
        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_request(method, url, parameters: { key: "value" })
        end.to output(%r{GET https://example.com}).to_stdout
      end

      it "prints parameters" do
        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_request(method, url, parameters: { key: "value" })
        end.to output(/Parameters:/).to_stdout
      end

      it "prints headers" do
        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_request(method, url,
                                        headers: { "Content-Type": "application/json" })
        end.to output(/Headers:/).to_stdout
      end

      it "prints body" do
        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_request(method, url, body: { data: "test" })
        end.to output(/Body:/).to_stdout
      end
    end

    context "when debug mode is off" do
      before { allow(described_class).to receive(:debug?).and_return(false) }

      it "does not print anything" do
        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_request(method, url)
        end.not_to output.to_stdout
      end
    end
  end

  describe ".debug_page" do
    let(:page) { double("Mechanize::Page") }
    let(:message) { "Test debug page" }

    context "when debug mode is on" do
      before { allow(described_class).to receive(:debug?).and_return(true) }

      it "prints page details" do
        allow(page).to receive(:uri).and_return("https://example.com")
        allow(page).to receive(:at).with("title").and_return(double(text: "Test Page"))
        allow(page).to receive(:body).and_return("<html>Test Content</html>")

        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_page(page, message)
        end.to output(/DEBUG: Test debug page/).to_stdout
      end

      it "handles missing title" do
        allow(page).to receive(:uri).and_return("https://example.com")
        allow(page).to receive(:at).with("title").and_return(nil)
        allow(page).to receive(:body).and_return("<html>Test Content</html>")

        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_page(page, message)
        end.to output(/DEBUG: Test debug page/).to_stdout
      end
    end

    context "when debug mode is off" do
      before { allow(described_class).to receive(:debug?).and_return(false) }

      it "does not print anything" do
        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_page(page, message)
        end.not_to output.to_stdout
      end
    end
  end

  describe ".debug_selector" do
    let(:page) { double("Mechanize::Page") }
    let(:selector) { "div.test" }
    let(:message) { "Test selector" }

    context "when debug mode is on" do
      before { allow(described_class).to receive(:debug?).and_return(true) }

      it "prints selector details when element found" do
        element = double(to_html: '<div class="test">Test Content</div>')
        allow(page).to receive(:at).with(selector).and_return(element)

        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_selector(page, selector, message)
        end.to output(/DEBUG: Test selector/).to_stdout
      end

      it "prints page body when element not found" do
        allow(page).to receive(:at).with(selector).and_return(nil)
        allow(page).to receive(:body).and_return("<html>Test Content</html>")

        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_selector(page, selector, message)
        end.to output(/Element not found/).to_stdout
      end
    end

    context "when debug mode is off" do
      before { allow(described_class).to receive(:debug?).and_return(false) }

      it "does not print anything" do
        expect do
          # noinspection RubyMismatchedArgumentType
          described_class.debug_selector(page, selector, message)
        end.not_to output.to_stdout
      end
    end
  end
end
