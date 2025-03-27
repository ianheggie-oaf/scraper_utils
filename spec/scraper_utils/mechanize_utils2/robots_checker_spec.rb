# frozen_string_literal: true

require_relative "../../spec_helper"
require "net/http"
require "uri"

RSpec.describe ScraperUtils::MechanizeUtils::RobotsChecker do
  subject(:robots_checker) { described_class.new(user_agent) }

  let(:user_agent) { "Mozilla/5.0 (compatible; ScraperUtils/1.0.0 2025-02-23; +https://github.com/example/scraper)" }

  after do
    ENV["DEBUG"] = nil
  end

  describe "#get_rules" do
    let(:domain) { "https://example.com" }
    
    it "returns nil when robots.txt fetch fails" do
      # Stub a failed request
      stub_request(:get, "#{domain}/robots.txt")
        .to_return(status: 404)
      
      # Call the private method directly for testing
      rules = robots_checker.send(:get_rules, domain)
      
      expect(rules).to be_nil
    end
    
    it "returns nil when robots.txt fetch raises an error" do
      # Stub a request that raises an error
      stub_request(:get, "#{domain}/robots.txt")
        .to_raise(StandardError.new("Connection error"))
      
      # Call the private method directly for testing
      rules = robots_checker.send(:get_rules, domain)
      
      expect(rules).to be_nil
    end
    
    it "caches rules for subsequent calls" do
      # Stub a successful request
      stub_request(:get, "#{domain}/robots.txt")
        .to_return(status: 200, body: "User-agent: *\nDisallow: /private/")
      
      # First call should make the HTTP request
      first_rules = robots_checker.send(:get_rules, domain)
      
      # Modify the cached rules to verify they're being used
      robots_checker.instance_variable_get(:@rules)[domain] = { test: true }
      
      # Second call should use cached rules
      second_rules = robots_checker.send(:get_rules, domain)
      
      expect(second_rules).to eq({ test: true })
    end
  end

  describe "#parse_robots_txt" do
    it "handles empty robots.txt content" do
      rules = robots_checker.send(:parse_robots_txt, "")
      
      expect(rules[:our_rules]).to eq([])
      expect(rules[:our_delay]).to be_nil
    end
    
    it "handles robots.txt with only comments" do
      content = <<~ROBOTS
        # This is a comment
        # Another comment
      ROBOTS
      
      rules = robots_checker.send(:parse_robots_txt, content)
      
      expect(rules[:our_rules]).to eq([])
      expect(rules[:our_delay]).to be_nil
    end
    
    it "handles robots.txt with specific user agent matching our bot" do
      content = <<~ROBOTS
        User-agent: scraperutils
        Disallow: /private/
        Crawl-delay: 5
        
        User-agent: *
        Disallow: /
        Crawl-delay: 10
      ROBOTS
      
      rules = robots_checker.send(:parse_robots_txt, content)
      
      expect(rules[:our_rules]).to eq(["/private/"])
      expect(rules[:our_delay]).to eq(5)
    end
    
    it "handles robots.txt with specific agent that matches beginning of our user agent" do
      content = <<~ROBOTS
        User-agent: scraper
        Disallow: /specific/
        Crawl-delay: 3
        
        User-agent: *
        Disallow: /
        Crawl-delay: 10
      ROBOTS
      
      rules = robots_checker.send(:parse_robots_txt, content)
      
      expect(rules[:our_rules]).to eq(["/specific/"])
      expect(rules[:our_delay]).to eq(3)
    end
    
    it "falls back to default rules when no specific rules match" do
      content = <<~ROBOTS
        User-agent: googlebot
        Disallow: /private/
        Crawl-delay: 5
        
        User-agent: *
        Disallow: /public/
        Crawl-delay: 7
      ROBOTS
      
      rules = robots_checker.send(:parse_robots_txt, content)
      
      expect(rules[:our_rules]).to eq([])
      expect(rules[:our_delay]).to eq(7)
    end
    
    it "handles continued user agent sections" do
      content = <<~ROBOTS
        User-agent: googlebot
        User-agent: bingbot
        User-agent: scraperutils
        Disallow: /shared/
        Crawl-delay: 6
      ROBOTS
      
      rules = robots_checker.send(:parse_robots_txt, content)
      
      expect(rules[:our_rules]).to eq(["/shared/"])
      expect(rules[:our_delay]).to eq(6)
    end
    
    it "handles multiple disallow rules" do
      content = <<~ROBOTS
        User-agent: scraperutils
        Disallow: /private/
        Disallow: /admin/
        Disallow: /secure/
        Crawl-delay: 4
      ROBOTS
      
      rules = robots_checker.send(:parse_robots_txt, content)
      
      expect(rules[:our_rules]).to contain_exactly("/private/", "/admin/", "/secure/")
      expect(rules[:our_delay]).to eq(4)
    end
    
    it "ignores empty disallow rules" do
      content = <<~ROBOTS
        User-agent: scraperutils
        Disallow:
        Disallow: /admin/
        Crawl-delay: 4
      ROBOTS
      
      rules = robots_checker.send(:parse_robots_txt, content)
      
      expect(rules[:our_rules]).to contain_exactly("/admin/")
    end
    
    it "ignores invalid crawl-delay values" do
      content = <<~ROBOTS
        User-agent: scraperutils
        Disallow: /private/
        Crawl-delay: invalid
      ROBOTS
      
      rules = robots_checker.send(:parse_robots_txt, content)
      
      expect(rules[:our_delay]).to be_nil
    end
    
    it "handles rules outside a user-agent section" do
      content = <<~ROBOTS
        Disallow: /before/
        
        User-agent: scraperutils
        Disallow: /private/
      ROBOTS
      
      rules = robots_checker.send(:parse_robots_txt, content)
      
      expect(rules[:our_rules]).to eq(["/private/"])
    end
  end
end
