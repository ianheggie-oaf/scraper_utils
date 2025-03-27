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
    if Fiber.current != ScraperUtils::Scheduler::Constants::MAIN_FIBER
      puts "WARNING: Had to resume main fiber"
      ScraperUtils::Scheduler::Constants::MAIN_FIBER.resume
    end
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
                 "max_load=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_MAX_LOAD}%\n"
                ].join(' ')
              ).to_stdout
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
                  "max_load=#{ScraperUtils::MechanizeUtils::AgentConfig::DEFAULT_MAX_LOAD}%\n"
                 ].join(' ')
               ).to_stdout
      end
    end
  end
end
