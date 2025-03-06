# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::MechanizeActions do
  let(:agent) { Mechanize.new }
  # Initialize with the agent as required by the class
  let(:mechanize_actions) { described_class.new(agent) }
  # For tests that need replacements
  let(:mechanize_actions_with_replacements) do
    replacements = { "USERNAME" => "testuser", "PASSWORD" => "password123" }
    described_class.new(agent, replacements)
  end

  let(:test_html) do
    <<~HTML
      <html>
        <body>
          <a href="/normal-link">Normal Link</a>
          <a href="#fragment-link">Fragment Link</a>
          <a href="/duplicate-text">Duplicate Text</a>
          <a href="/another-path">Duplicate Text</a>
          <a href="/option1">Option 1</a>
          <a href="/option2">Option 2</a>
          <form action="/submit" method="post">
            <input type="text" name="username" />
            <input type="password" name="password" />
            <input type="submit" value="Login" />
          </form>
          <div class="css-selector">CSS Selectable Element</div>
          <div id="xpath-element">XPath Selectable Element</div>
        </body>
      </html>
    HTML
  end

  before do
    stub_request(:get, "http://example.com/")
      .to_return(status: 200, body: test_html, headers: { 'Content-Type' => 'text/html' })

    stub_request(:get, "http://example.com/normal-link")
      .to_return(status: 200, body: "<html><body>Normal Link Page</body></html>", headers: { 'Content-Type' => 'text/html' })

    stub_request(:get, "http://example.com/duplicate-text")
      .to_return(status: 200, body: "<html><body>Duplicate Text Page</body></html>", headers: { 'Content-Type' => 'text/html' })

    stub_request(:get, "http://example.com/option1")
      .to_return(status: 200, body: "<html><body>Option 1 Page</body></html>", headers: { 'Content-Type' => 'text/html' })

    stub_request(:get, "http://example.com/option2")
      .to_return(status: 200, body: "<html><body>Option 2 Page</body></html>", headers: { 'Content-Type' => 'text/html' })

    stub_request(:post, "http://example.com/submit")
      .with(body: {"password" => "password123", "username" => "testuser"})
      .to_return(status: 200, body: "<html><body>Form Submitted</body></html>", headers: { 'Content-Type' => 'text/html' })
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

    it "applies replacements to action parameters" do
      replacements = { "TEST" => "Option 1" }
      action_processor = described_class.new(agent, replacements)
      
      actions = [
        [:click, "{TEST}"]
      ]

      result = action_processor.process(page, actions)

      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("Option 1 Page")
      expect(action_processor.results[0][:action]).to eq(:click)
      expect(action_processor.results[0][:target]).to eq("Option 1")
    end

    it "handles case-insensitive matching when no exact match found" do
      actions = [
        [:click, "NORMAL link"]
      ]

      result = mechanize_actions.process(page, actions)

      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("Normal Link Page")
      expect(mechanize_actions.results[0][:action]).to eq(:click)
      expect(mechanize_actions.results[0][:target]).to eq("NORMAL link")
    end

    it "raises an error when no matching links are found" do
      actions = [
        [:click, "Non-existent link"]
      ]

      expect { mechanize_actions.process(page, actions) }.to raise_error(/Unable to find click target/)
    end

    it "executes a block action" do
      custom_result = { custom: "value" }
      next_page = instance_double("Mechanize::Page")
      
      block = lambda do |current_page, args, agent, results|
        expect(current_page).to eq(page)
        [next_page, custom_result]
      end

      actions = [
        [:block, block]
      ]

      result = mechanize_actions.process(page, actions)

      expect(result).to eq(next_page)
      expect(mechanize_actions.results[0]).to eq(custom_result)
    end

    it "raises an error for unknown action types" do
      actions = [
        [:unknown_action, "some value"]
      ]

      expect { mechanize_actions.process(page, actions) }.to raise_error(ArgumentError, /Unknown action type/)
    end

    it "processes multiple actions in sequence" do
      # Setup first click to normal-link
      normal_link_page = agent.get("http://example.com/normal-link")
      
      # Setup second destination - an additional stub for the normal-link page that includes an Option 1 link
      normal_link_html = <<~HTML
        <html>
          <body>
            Normal Link Page
            <a href="/option1">Option 1</a>
          </body>
        </html>
      HTML
      
      stub_request(:get, "http://example.com/normal-link")
        .to_return(status: 200, body: normal_link_html, headers: { 'Content-Type' => 'text/html' })
        
      # This is what we expect to get after clicking Option 1 from the normal-link page
      stub_request(:get, "http://example.com/option1")
        .to_return(status: 200, body: "<html><body>Option 1 from Normal Link</body></html>", headers: { 'Content-Type' => 'text/html' })

      actions = [
        [:click, "Normal Link"],
        [:click, "Option 1"]
      ]

      result = mechanize_actions.process(page, actions)

      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("Option 1 from Normal Link")
      expect(mechanize_actions.results.size).to eq(2)
      expect(mechanize_actions.results[0][:action]).to eq(:click)
      expect(mechanize_actions.results[0][:target]).to eq("Normal Link")
      expect(mechanize_actions.results[1][:action]).to eq(:click)
      expect(mechanize_actions.results[1][:target]).to eq("Option 1")
    end
  end
end
