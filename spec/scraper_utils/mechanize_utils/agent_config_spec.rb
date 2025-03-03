# frozen_string_literal: true

require_relative "../../spec_helper"

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

  after do
    ENV["MORPH_AUSTRALIAN_PROXY"] = nil
    ENV["DEBUG"] = nil
  end

  describe "#initialize" do
    context "with no options" do
      it "creates default configuration and displays it" do
        expect { described_class.new }
          .to output(
                ["Configuring Mechanize agent with",
                 "timeout=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_TIMEOUT},",
                 "australian_proxy=false, compliant_mode,",
                 "random_delay=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_RANDOM_DELAY},",
                 "max_load=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_MAX_LOAD}%\n"
                ].join(' ')
              ).to_stdout
      end
    end

    context "with debug logging" do
      before { ENV["DEBUG"] = "2" }

      it "logs connection details" do
        config = described_class.new
        config.configure_agent(Mechanize.new)
        expect do
          config.send(:pre_connect_hook, nil, double(inspect: "test request"))
        end.to output(/Pre Connect request: test request/).to_stdout
      end
    end

    context "with default configuration" do
      it "creates default configuration with default max load" do
        expect { described_class.new }.to output(
                                            /max_load=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_MAX_LOAD}%/
                                          ).to_stdout
      end
    end

    context "with compliant mode" do
      it "caps max_load when compliant mode is true" do
        config = described_class.new(max_load: 999.0, compliant_mode: true)
        expect(config.max_load).to eq(ScraperUtils::MechanizeUtils::AgentConfig::MAX_LOAD_CAP)
      end
    end

    context "with all options enabled" do
      it "creates configuration with all options and displays them" do
        message_part1 = "Configuring Mechanize agent with timeout=30, australian_proxy=true,"
        message_part2 = "compliant_mode, random_delay=5, max_load=15.0%, disable_ssl_certificate_check"

        expect do
          described_class.new(
            australian_proxy: true,
            timeout: 30,
            compliant_mode: true,
            random_delay: 5,
            max_load: 15.0,
            disable_ssl_certificate_check: true
          )
        end.to output(/#{Regexp.escape(message_part1)} #{Regexp.escape(message_part2)}/m).to_stdout
      end
    end

    context "with proxy configuration edge cases" do
      it "handles proxy without australian_proxy authority" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = "https://example.com:8888/"
        expect do
          described_class.new(australian_proxy: true)
        end.to output(
                 ["Configuring Mechanize agent with",
                  "timeout=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_TIMEOUT},",
                  "australian_proxy=true, compliant_mode,",
                  "random_delay=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_RANDOM_DELAY},",
                  "max_load=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_MAX_LOAD}%\n"
                 ].join(' ')
               ).to_stdout
      ensure
        ENV["MORPH_AUSTRALIAN_PROXY"] = nil
      end

      it "handles empty proxy URL" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = ""
        expect do
          described_class.new(australian_proxy: true)
        end.to output(
                 ["Configuring Mechanize agent with",
                  "timeout=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_TIMEOUT},",
                  "MORPH_AUSTRALIAN_PROXY not set, compliant_mode,",
                  "random_delay=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_RANDOM_DELAY},",
                  "max_load=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_MAX_LOAD}%\n"
                 ].join(' ')
               ).to_stdout
      end
    end

    context "with debug logging" do
      before { ENV["DEBUG"] = "2" }

      it "logs connection details" do
        config = described_class.new
        config.configure_agent(Mechanize.new)
        expect do
          config.send(:pre_connect_hook, nil, double(inspect: "test request"))
        end.to output(/Pre Connect request: test request/).to_stdout
      end
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

      it "logs delay details when delay applied" do
        config = described_class.new(random_delay: 1, user_agent: "TestAgent")
        uri = URI("https://example.com")
        response = double(inspect: "test response")
        # required for post_connect_hook
        config.send(:pre_connect_hook, nil, nil)
        expect do
          config.send(:post_connect_hook, nil, uri, response, nil)
        end.to output(/Delaying \d+\.\d+ seconds/).to_stdout
      end
    end
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

    context "with proxy verification" do
      it "handles invalid IP formats" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = proxy_url
        stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
          .to_return(body: "invalid.ip.address\n")
        # force use of new public_ip
        ScraperUtils::MechanizeUtils.public_ip(nil, force: true)
        config = described_class.new(australian_proxy: true)
        expect do
          config.configure_agent(agent)
        end.to raise_error(/Invalid public IP address returned by proxy check/)
      end

      it "handles proxy connection timeout" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = proxy_url
        stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
          .to_timeout
        # force use of new public_ip
        ScraperUtils::MechanizeUtils.public_ip(nil, force: true)

        config = described_class.new(australian_proxy: true)
        expect do
          config.configure_agent(agent)
        end.to raise_error(/Proxy check timed out/)
      end

      it "handles proxy connection refused" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = proxy_url
        stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
          .to_raise(Errno::ECONNREFUSED)
        # force use of new public_ip
        ScraperUtils::MechanizeUtils.public_ip(nil, force: true)

        config = described_class.new(australian_proxy: true)
        expect do
          config.configure_agent(agent)
        end.to raise_error(/Failed to connect to proxy/)
      end

      it "handles proxy authentication failure" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = proxy_url
        stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
          .to_return(status: [407, "Proxy Authentication Required"])
        # force use of new public_ip
        ScraperUtils::MechanizeUtils.public_ip(nil, force: true)

        config = described_class.new(australian_proxy: true)
        expect do
          config.configure_agent(agent)
        end.to raise_error(/Proxy check error/)
      end

      it "handles malformed proxy URL" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = "not-a-valid-url"
        # force use of new public_ip
        ScraperUtils::MechanizeUtils.public_ip(nil, force: true)

        expect do
          config = described_class.new(australian_proxy: true)
          config.configure_agent(agent)
        end.to raise_error(URI::InvalidURIError)
      end

      it "handles JSON parsing errors in public headers" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = proxy_url
        stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
          .to_return(body: "1.2.3.4\n")
        stub_request(:get, ScraperUtils::MechanizeUtils::HEADERS_ECHO_URL)
          .to_return(body: "Not a valid JSON")

        # Force clearing of cached public headers and IP
        ScraperUtils::MechanizeUtils.instance_variable_set(:@public_ip, nil)
        ScraperUtils::MechanizeUtils.instance_variable_set(:@public_headers, nil)

        config = described_class.new(australian_proxy: true)
        expect do
          config.configure_agent(agent)
        end.to output(/Couldn't parse public_headers/).to_stdout
      end
    end

    context "with post_connect_hook" do
      it "requires a URI" do
        config = described_class.new
        config.configure_agent(agent)
        hook = agent.post_connect_hooks.first

        expect do
          hook.call(agent, nil, double("response"), "body")
        end.to raise_error(ArgumentError, "URI must be present in post-connect hook")
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
          config.default_compliant_mode = false
          config.default_random_delay = 99
          config.default_max_load = 50.0
          config.default_disable_ssl_certificate_check = true
          config.default_australian_proxy = true
          config.default_user_agent = "Test Agent"
        end

        described_class.reset_defaults!

        expect(described_class.default_timeout).to eq(ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_TIMEOUT)
        expect(described_class.default_compliant_mode).to be(true)
        expect(described_class.default_random_delay).to eq(ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_RANDOM_DELAY)
        expect(described_class.default_max_load).to eq(ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_MAX_LOAD)
        expect(described_class.default_disable_ssl_certificate_check).to be(false)
        expect(described_class.default_australian_proxy).to eq(false)
        expect(described_class.default_user_agent).to be_nil
      end
    end
  end

  describe "random delay calculation" do
    it "calculates min and max random delays correctly" do
      config = described_class.new(random_delay: 5)

      expect(config.min_random).to be_within(0.01).of(Math.sqrt(5 * 3.0 / 13.0))
      expect(config.max_random).to be_within(0.01).of(3 * config.min_random)
    end

    it "handles nil random delay when default is also nil" do
      described_class.configure do |config|
        config.default_random_delay = nil
      end
      config = described_class.new(random_delay: nil)

      expect(config.min_random).to be_nil
      expect(config.max_random).to be_nil
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
        config = described_class.new(compliant_mode: true)
        expect(config.user_agent).to include(/\d{4}-\d\d-\d\d/)
      end
    end

    context "with default compliant mode" do
      it "generates a default user agent with ScraperUtils version" do
        config = described_class.new(compliant_mode: true)
        expect(config.user_agent).to match(%r{ScraperUtils/\d+\.\d+\.\d+})
        expect(config.user_agent).to include("+https://github.com/ianheggie-oaf/scraper_utils")
      end
    end
  end
end
