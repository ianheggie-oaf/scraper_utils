# frozen_string_literal: true

require_relative "../../spec_helper"
require "mechanize"
require "webmock/rspec"

RSpec.describe ScraperUtils::MechanizeActions do
  let(:agent) { Mechanize.new }
  let(:mechanize_actions) { described_class.new(agent) }

  before do
    # Create a test page with multiple selector types
    stub_request(:get, "http://example.com/selectors")
      .to_return(status: 200, body: <<~HTML, headers: { 'Content-Type' => 'text/html' })
        <html>
          <body>
            <div class="css-class">CSS Selector Element</div>
            <div id="xpath-id">XPath Selector Element</div>
            <a href="/css-link">CSS Link</a>
            <a href="/xpath-link">XPath Link</a>
          </body>
        </html>
      HTML

    # Target pages
    stub_request(:get, "http://example.com/css-link")
      .to_return(status: 200, body: "<html><body>CSS Link Page</body></html>", 
                headers: { 'Content-Type' => 'text/html' })
                
    stub_request(:get, "http://example.com/xpath-link")
      .to_return(status: 200, body: "<html><body>XPath Link Page</body></html>", 
                headers: { 'Content-Type' => 'text/html' })
  end

  describe "#select_element" do
    let(:page) { agent.get("http://example.com/selectors") }
    
    it "selects elements using CSS selector" do
      # Test the private method directly
      element = mechanize_actions.send(:select_element, page, "css:.css-class")
      
      expect(element).to be_a(Nokogiri::XML::Element)
      expect(element.text).to eq("CSS Selector Element")
    end
    
    it "selects elements using XPath selector" do
      # Test the private method directly
      element = mechanize_actions.send(:select_element, page, "xpath://div[@id='xpath-id']")
      
      expect(element).to be_a(Nokogiri::XML::Element)
      expect(element.text).to eq("XPath Selector Element")
    end
    
    it "selects links with CSS selectors" do
      # Test that the private select_element method returns the right link
      element = mechanize_actions.send(:select_element, page, "css:a[href='/css-link']")
      
      expect(element).to be_a(Mechanize::Page::Link)
      expect(element.text).to eq("CSS Link")
      expect(element.href).to eq("/css-link")
      
      # Now test clicking through the public API
      actions = [
        [:click, "css:a[href='/css-link']"]
      ]
      
      result = mechanize_actions.process(page, actions)
      
      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("CSS Link Page")
      expect(mechanize_actions.results[0][:action]).to eq(:click)
      expect(mechanize_actions.results[0][:target]).to eq("css:a[href='/css-link']")
    end
    
    it "selects links with XPath selectors" do
      # Test that the private select_element method returns the right link
      element = mechanize_actions.send(:select_element, page, "xpath://a[@href='/xpath-link']")
      
      expect(element).to be_a(Mechanize::Page::Link)
      expect(element.text).to eq("XPath Link")
      expect(element.href).to eq("/xpath-link")
      
      # Now test clicking through the public API
      actions = [
        [:click, "xpath://a[@href='/xpath-link']"]
      ]
      
      result = mechanize_actions.process(page, actions)
      
      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("XPath Link Page")
      expect(mechanize_actions.results[0][:action]).to eq(:click)
      expect(mechanize_actions.results[0][:target]).to eq("xpath://a[@href='/xpath-link']")
    end
    
    it "returns nil when element not found" do
      element = mechanize_actions.send(:select_element, page, "css:.non-existent")
      
      expect(element).to be_nil
    end
    
    it "prioritizes shortest text match for text selectors" do
      # Create a page with multiple possible matches
      stub_request(:get, "http://example.com/multiple-matches")
        .to_return(status: 200, body: <<~HTML, headers: { 'Content-Type' => 'text/html' })
          <html>
            <body>
              <a href="/link1">Match</a>
              <a href="/link2">Match with more text</a>
              <a href="/link3">Another Match</a>
            </body>
          </html>
        HTML
        
      stub_request(:get, "http://example.com/link1")
        .to_return(status: 200, body: "<html><body>Link 1</body></html>")
      
      page = agent.get("http://example.com/multiple-matches")
      
      actions = [
        [:click, "Match"]
      ]
      
      result = mechanize_actions.process(page, actions)
      
      expect(result.body).to include("Link 1")
    end
  end
  
  describe "advanced handling" do
    it "executes a block action" do
      page = agent.get("http://example.com/selectors")
      
      custom_result = { custom: "value" }
      next_page = agent.get("http://example.com/selectors") # Use a real page
      
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
    
    it "processes multiple actions in sequence" do
      # Setup first page with a link
      stub_request(:get, "http://example.com/sequence")
        .to_return(status: 200, body: <<~HTML, headers: { 'Content-Type' => 'text/html' })
          <html>
            <body>
              <a href="/first">First Link</a>
            </body>
          </html>
        HTML
      
      # Setup second page with a link
      stub_request(:get, "http://example.com/first")
        .to_return(status: 200, body: <<~HTML, headers: { 'Content-Type' => 'text/html' })
          <html>
            <body>
              <a href="/second">Second Link</a>
            </body>
          </html>
        HTML
      
      # Setup final page
      stub_request(:get, "http://example.com/second")
        .to_return(status: 200, body: "<html><body>Final Page</body></html>",
                  headers: { 'Content-Type' => 'text/html' })
      
      page = agent.get("http://example.com/sequence")
      
      actions = [
        [:click, "First Link"],
        [:click, "Second Link"]
      ]
      
      result = mechanize_actions.process(page, actions)
      
      expect(result).to be_a(Mechanize::Page)
      expect(result.body).to include("Final Page")
      expect(mechanize_actions.results.size).to eq(2)
      expect(mechanize_actions.results[0][:action]).to eq(:click)
      expect(mechanize_actions.results[0][:target]).to eq("First Link")
      expect(mechanize_actions.results[1][:action]).to eq(:click)
      expect(mechanize_actions.results[1][:target]).to eq("Second Link")
    end
  end
end
