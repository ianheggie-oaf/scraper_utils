# frozen_string_literal: true

require_relative "../../../spec_helper"

RSpec.describe ScraperUtils::MechanizeUtils::AgentConfig do
  let(:proxy_url) { "https://user:password@test.proxy:8888" }

  before do
    stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
      .to_return(body: "1.2.3.4\n")
    stub_request(:get, ScraperUtils::MechanizeUtils::HEADERS_ECHO_URL)
      .to_return(body: '{"headers":{"Host":"httpbin.org"}}')
    stub_request(:get, "https://example.com/robots.txt")
      .to_return(body: "User-agent: *\nDisallow: /\n")

    # force use of new public_ip
    ScraperUtils::MechanizeUtils.public_ip(nil, force: true)
    ENV["MORPH_AUSTRALIAN_PROXY"] = proxy_url
  end

  after(:all) do
    ENV["MORPH_AUSTRALIAN_PROXY"] = nil
    ENV["DEBUG"] = nil
  end

  describe "#configure_agent" do
    let(:agent) { Mechanize.new }

    context "with timeout configuration" do
      it "sets both read and open timeouts when specified" do
        config = described_class.new(timeout: 42)
        config.configure_agent(agent)
        expect(agent.open_timeout).to eq(42)
        expect(agent.read_timeout).to eq(42)
      end

      it "does not set timeouts when not specified" do
        agent = Mechanize.new
        agent.open_timeout = nil
        agent.read_timeout = nil

        config = described_class.new
        config.configure_agent(agent)

        expect(agent.open_timeout).to eq(60)
        expect(agent.read_timeout).to eq(60)
      end
    end

    it "configures SSL verification when requested" do
      config = described_class.new(disable_ssl_certificate_check: true)
      config.configure_agent(agent)
      expect(agent.verify_mode).to eq(OpenSSL::SSL::VERIFY_NONE)
    end

    it "configures proxy when available and requested" do
      config = described_class.new(australian_proxy: true)
      config.configure_agent(agent)
      expect(agent.agent.proxy_uri.to_s).to eq(proxy_url)
    end

    it "sets up pre and post connect hooks" do
      config = described_class.new
      config.configure_agent(agent)
      expect(agent.pre_connect_hooks.size).to eq(1)
      expect(agent.post_connect_hooks.size).to eq(1)
    end

    context "with post_connect_hook" do
      before do
        ENV["DEBUG"] = "1"
        stub_request(:get, "https://example.com/robots.txt")
          .to_return(status: 200, body: "User-agent: *\nAllow: /\n")
      end

      it "logs connection details" do
        config = described_class.new(user_agent: "TestAgent")
        uri = URI("https://example.com")
        response = double(inspect: "test response")
        # required for post_connect_hook
        config.send(:pre_connect_hook, nil, nil)
        expect do
          config.send(:post_connect_hook, nil, uri, response, nil)
        end.to output(/Post Connect uri:.*response: test response/m).to_stdout
      end
    end
  end

  describe "class methods" do
    describe ".configure" do
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

    describe ".reset_defaults!" do
      it "resets all configuration options to their default values" do
        described_class.configure do |config|
          config.default_timeout = 999
          config.default_disable_ssl_certificate_check = true
          config.default_australian_proxy = true
          config.default_user_agent = "Test Agent"
        end

        described_class.reset_defaults!

        expect(described_class.default_timeout).to eq(ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_TIMEOUT)
        expect(described_class.default_disable_ssl_certificate_check).to be(false)
        expect(described_class.default_australian_proxy).to eq(false)
        expect(described_class.default_user_agent).to be_nil
      end
    end
  end

  describe "user agent configuration" do
    context "with ENV['MORPH_USER_AGENT']" do
      before do
        ENV["MORPH_USER_AGENT"] = "TestAgent-TODAY"
        ENV["MORPH_TODAY"] = "2025-02-27"
      end

      after do
        ENV["MORPH_USER_AGENT"] = nil
        ENV["MORPH_TODAY"] = nil
      end

      it "replaces TODAY with current date" do
        config = described_class.new
        expect(config.user_agent).to include(/\d{4}-\d\d-\d\d/)
      end
    end

    context "with default compliant mode" do
      it "generates a default user agent with ScraperUtils version" do
        config = described_class.new
        expect(config.user_agent).to match(%r{ScraperUtils/\d+\.\d+\.\d+})
        expect(config.user_agent).to include("+https://github.com/ianheggie-oaf/scraper_utils")
      end
    end
  end
end
