# frozen_string_literal: true

require_relative "../../spec_helper"
require "mechanize"
require "webmock/rspec"

RSpec.describe ScraperUtils::MechanizeActions do
  let(:agent) { Mechanize.new }
  
  before do
    # Create a test page with links that can use replacements
    stub_request(:get, "http://example.com/")
      .to_return(status: 200, body: <<~HTML, headers: { 'Content-Type' => 'text/html' })
        <html>
          <body>
            <a href="/option1">Option 1</a>
            <a href="/search?date=today">Search Today</a>
            <a href="/search?user=admin">Admin Search</a>
            <a href="/match-test">Test Match</a>
          </body>
        </html>
      HTML

    # Target pages
    stub_request(:get, "http://example.com/option1")
      .to_return(status: 200, body: "<html><body>Option 1 Page</body></html>", 
                headers: { 'Content-Type' => 'text/html' })
                
    stub_request(:get, "http://example.com/search?date=2025-03-12")
      .to_return(status: 200, body: "<html><body>Search Results for 2025-03-12</body></html>", 
                headers: { 'Content-Type' => 'text/html' })
                
    stub_request(:get, "http://example.com/search?user=testuser")
      .to_return(status: 200, body: "<html><body>Search Results for testuser</body></html>", 
                headers: { 'Content-Type' => 'text/html' })
  end
  
  describe "#process with replacements" do
    let(:page) { agent.get("http://example.com/") }
    
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
    
    it "handles multiple replacements in one parameter" do
      # Create a special test page with replacements in parameters
      stub_request(:get, "http://example.com/replacements-page")
        .to_return(status: 200, body: <<~HTML, headers: { 'Content-Type' => 'text/html' })
          <html>
            <body>
              <a href="/search?date=2025-03-12">Search for dates</a>
            </body>
          </html>
        HTML
      
      replacements = { 
        "DATE" => "2025-03-12", 
        "SEARCH_TEXT" => "Search for dates" 
      }
      action_processor = described_class.new(agent, replacements)
      
      replacement_page = agent.get("http://example.com/replacements-page")
      
      actions = [
        [:click, "{SEARCH_TEXT}"]
      ]

      result = action_processor.process(replacement_page, actions)

      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("Search Results for 2025-03-12")
      expect(action_processor.results[0][:target]).to eq("Search for dates")
    end
    
    it "applies replacements to an array of options" do
      replacements = { "OPT" => "Option 1" }
      action_processor = described_class.new(agent, replacements)
            
      actions = [
        [:click, ["Invalid Option", "{OPT}", "Other Option"]]
      ]
      
      # Force CycleUtils to pick the option with replacement
      allow(ScraperUtils::CycleUtils).to receive(:pick).and_return("{OPT}")

      result = action_processor.process(page, actions)

      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("Option 1 Page")
      expect(action_processor.results[0][:target]).to eq("Option 1")
    end
    
    it "handles case-insensitive matching when no exact match found" do
      # Create a page with case-sensitive text
      stub_request(:get, "http://example.com/case-test")
        .to_return(status: 200, body: <<~HTML, headers: { 'Content-Type' => 'text/html' })
          <html>
            <body>
              <a href="/option1">Test Match</a>
            </body>
          </html>
        HTML
      
      replacements = { "TEXT" => "test match" }
      action_processor = described_class.new(agent, replacements)
      
      case_page = agent.get("http://example.com/case-test")
      
      actions = [
        [:click, "{TEXT}"]
      ]

      result = action_processor.process(case_page, actions)

      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("Option 1 Page")
    end
    
    it "applies replacements to block arguments" do
      replacements = { "DATA" => "custom data" }
      action_processor = described_class.new(agent, replacements)
      
      received_args = nil
      
      # Create a test page
      test_page = page
      
      actions = [
        [:block, lambda do |page, args, agent, results|
          # Capture the arguments passed to the block
          received_args = args  
          # Return page and result
          [page, { custom: "result" }]
        end, "{DATA}"]
      ]

      # Process the actions
      action_processor.process(test_page, actions)
      
      # Verify the replacement was applied to the block arguments
      expect(received_args).to eq("custom data")
    end
  end
  
  describe "#apply_replacements" do
    it "handles non-string values" do
      replacements = { "NUM" => 42 }
      action_processor = described_class.new(agent, replacements)
      
      # Call private method for testing
      result = action_processor.send(:apply_replacements, "{NUM}")
      
      expect(result).to eq("42")
    end
    
    it "does nothing when no replacements match" do
      replacements = { "FOO" => "bar" }
      action_processor = described_class.new(agent, replacements)
      
      # Call private method for testing
      result = action_processor.send(:apply_replacements, "{BAZ}")
      
      expect(result).to eq("{BAZ}")
    end
    
    it "returns non-string values unchanged" do
      replacements = { "FOO" => "bar" }
      action_processor = described_class.new(agent, replacements)
      
      # Call private method for testing
      result = action_processor.send(:apply_replacements, 42)
      
      expect(result).to eq("42")
    end
  end
end
