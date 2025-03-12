# frozen_string_literal: true

require_relative "../../spec_helper"
require "mechanize"

RSpec.describe ScraperUtils::MechanizeActions do
  let(:agent) { Mechanize.new }
  let(:mechanize_actions) { described_class.new(agent) }
  let(:mechanize_actions_with_replacements) do
    replacements = { "USERNAME" => "testuser", "PASSWORD" => "password123" }
    described_class.new(agent, replacements)
  end

  before do
    stub_request(:get, "http://example.com/")
      .to_return(status: 200, body: <<~HTML, headers: { 'Content-Type' => 'text/html' })
        <html>
          <body>
            <a href="/normal-link">Normal Link</a>
            <a href="#fragment-link">Fragment Link</a>
            <a href="/duplicate-text">Duplicate Text</a>
            <a href="/another-path">Duplicate Text</a>
            <a href="/option1">Option 1</a>
            <a href="/option2">Option 2</a>
            <div class="css-selector">CSS Selectable Element</div>
            <div id="xpath-element">XPath Selectable Element</div>
          </body>
        </html>
      HTML

    stub_request(:get, "http://example.com/normal-link")
      .to_return(status: 200, body: "<html><body>Normal Link Page</body></html>", 
                headers: { 'Content-Type' => 'text/html' })

    stub_request(:get, "http://example.com/duplicate-text")
      .to_return(status: 200, body: "<html><body>Duplicate Text Page</body></html>", 
                headers: { 'Content-Type' => 'text/html' })

    stub_request(:get, "http://example.com/option1")
      .to_return(status: 200, body: "<html><body>Option 1 Page</body></html>", 
                headers: { 'Content-Type' => 'text/html' })

    stub_request(:get, "http://example.com/option2")
      .to_return(status: 200, body: "<html><body>Option 2 Page</body></html>", 
                headers: { 'Content-Type' => 'text/html' })
  end

  describe "#process" do
    let(:page) { agent.get("http://example.com/") }

    it "processes a series of click actions with text selectors" do
      actions = [
        [:click, "Normal Link"]
      ]

      result = mechanize_actions.process(page, actions)

      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("Normal Link Page")
      expect(mechanize_actions.results.size).to eq(1)
      expect(mechanize_actions.results[0][:action]).to eq(:click)
      expect(mechanize_actions.results[0][:target]).to eq("Normal Link")
    end

    it "prioritizes non-fragment links when selecting by text" do
      actions = [
        [:click, "Duplicate Text"]
      ]

      result = mechanize_actions.process(page, actions)

      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("Duplicate Text Page")
      expect(mechanize_actions.results[0][:action]).to eq(:click)
      expect(mechanize_actions.results[0][:target]).to eq("Duplicate Text")
    end

    it "selects from an array of options for a click action" do
      allow(ScraperUtils::CycleUtils).to receive(:pick).and_return("Option 1")
      
      actions = [
        [:click, ["Invalid Option", "Option 1", "Option 2"]]
      ]

      result = mechanize_actions.process(page, actions)

      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("Option 1 Page")
      expect(mechanize_actions.results[0][:action]).to eq(:click)
      expect(mechanize_actions.results[0][:target]).to eq("Option 1")
    end

    it "raises an error when no matching links are found" do
      actions = [
        [:click, "Non-existent link"]
      ]

      expect { mechanize_actions.process(page, actions) }
        .to raise_error(/Unable to find click target/)
    end

    it "raises an error for unknown action types" do
      actions = [
        [:unknown_action, "some value"]
      ]

      expect { mechanize_actions.process(page, actions) }
        .to raise_error(ArgumentError, /Unknown action type/)
    end
  end
end
