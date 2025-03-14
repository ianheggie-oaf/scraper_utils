# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::MechanizeUtils::AgentConfig do
  let(:proxy_url) { "https://user:password@test.proxy:8888" }

  before do
    stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL).to_return(body: "1.2.3.4\n")
    stub_request(:get, ScraperUtils::MechanizeUtils::HEADERS_ECHO_URL).to_return(body: '{"headers":{}}')
    stub_request(:get, "https://example.com/robots.txt").to_return(body: "User-agent: *\nDisallow: /\n")
    ScraperUtils::MechanizeUtils.public_ip(nil, force: true)
    ENV["MORPH_AUSTRALIAN_PROXY"] = proxy_url
  end

  after(:all) do
    if Fiber.current != ScraperUtils::Scheduler::Constants::MAIN_FIBER
      puts "WARNING: Had to resume main fiber"
      ScraperUtils::Scheduler::Constants::MAIN_FIBER.resume
    end
    ENV["MORPH_AUSTRALIAN_PROXY"] = nil
    ENV["DEBUG"] = nil
  end

  describe "#initialize" do
    it "creates configuration with default settings" do
      expect { described_class.new }
        .to output(/Configuring Mechanize agent/).to_stdout
    end
  end

  describe "#configure_agent" do
    let(:agent) { Mechanize.new }
    
    it "sets up the agent with the specified configuration" do
      config = described_class.new(timeout: 42)
      config.configure_agent(agent)
      
      expect(agent.open_timeout).to eq(42)
      expect(agent.read_timeout).to eq(42)
    end
  end
  
  describe "class methods" do
    it "allows configuration of default settings" do
      original_timeout = described_class.default_timeout
      
      described_class.configure do |config|
        config.default_timeout = 90
      end
      
      expect(described_class.default_timeout).to eq(90)
      
      # Reset to original value
      described_class.default_timeout = original_timeout
    end
  end
end

