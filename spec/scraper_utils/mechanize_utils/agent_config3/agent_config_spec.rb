# frozen_string_literal: true

require_relative "../../../spec_helper"

RSpec.describe ScraperUtils::MechanizeUtils::AgentConfig do
  before do
    stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
      .to_return(body: "1.2.3.4\n")
    stub_request(:get, ScraperUtils::MechanizeUtils::HEADERS_ECHO_URL)
      .to_return(body: '{"headers":{"Host":"httpbin.org"}}')
    stub_request(:get, "https://example.com/robots.txt")
      .to_return(body: "User-agent: *\nDisallow: /\n")

    # Force use of new public_ip
    ScraperUtils::MechanizeUtils.public_ip(nil, force: true)
  end

  after(:all) do
    ENV["MORPH_AUSTRALIAN_PROXY"] = nil
    ENV["DEBUG"] = nil
  end

  describe "#initialize" do
    context "with proxy validation" do
      it "validates proxy URL format" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = "invalid-url"
        
        expect {
          described_class.new(australian_proxy: true)
        }.to raise_error(URI::InvalidURIError, /Proxy URL must start with http/)
      end
      
      it "requires proxy URL to have a http(s) scheme" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = "ftp://proxy.example.com"
        
        expect {
          described_class.new(australian_proxy: true)
        }.to raise_error(URI::InvalidURIError, /Proxy URL must start with http/)
      end
      
      it "requires proxy URL to have host and port" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = "http://"
        
        expect {
          described_class.new(australian_proxy: true)
        }.to raise_error(URI::InvalidURIError, /Proxy URL must include host and port/)
      end

      it "accepts valid http proxy URL" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = "http://proxy.example.com:8080"
        
        expect {
          described_class.new(australian_proxy: true)
        }.not_to raise_error
      end
      
      it "accepts valid https proxy URL" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = "https://proxy.example.com:8080"
        
        expect {
          described_class.new(australian_proxy: true)
        }.not_to raise_error
      end
      
      it "accepts proxy URL with authentication" do
        ENV["MORPH_AUSTRALIAN_PROXY"] = "https://user:pass@proxy.example.com:8080"
        
        expect {
          described_class.new(australian_proxy: true)
        }.not_to raise_error
      end
    end
  end

  describe "#verify_proxy_works" do
    let(:agent) { Mechanize.new }
    
    it "raises error when proxy connection times out" do
      ENV["MORPH_AUSTRALIAN_PROXY"] = "http://test.proxy:8888"
      config = described_class.new(australian_proxy: true)
      
      # Stub timeout error for proxy check
      stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
        .to_raise(Timeout::Error.new("Proxy connection timed out"))
      
      expect {
        config.send(:verify_proxy_works, agent)
      }.to raise_error(/Proxy check timed out/)
    end
    
    it "raises error when proxy connection is refused" do
      ENV["MORPH_AUSTRALIAN_PROXY"] = "http://test.proxy:8888"
      config = described_class.new(australian_proxy: true)
      
      # Stub connection refused error for proxy check
      stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
        .to_raise(Errno::ECONNREFUSED.new("Connection refused"))
      
      expect {
        config.send(:verify_proxy_works, agent)
      }.to raise_error(/Failed to connect to proxy/)
    end
    
    it "raises error when proxy returns an error status" do
      ENV["MORPH_AUSTRALIAN_PROXY"] = "http://test.proxy:8888"
      config = described_class.new(australian_proxy: true)
      
      # Stub error response for proxy check
      stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
        .to_raise(Mechanize::ResponseCodeError.new(double("Response", code: "503")))
      
      expect {
        config.send(:verify_proxy_works, agent)
      }.to raise_error(/Proxy check error/)
    end
    
    it "raises error when proxy returns invalid IP address" do
      ENV["MORPH_AUSTRALIAN_PROXY"] = "http://test.proxy:8888"
      config = described_class.new(australian_proxy: true)
      
      # Stub invalid IP response
      stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
        .to_return(body: "not-an-ip-address")
      
      expect {
        config.send(:verify_proxy_works, agent)
      }.to raise_error(/Invalid public IP address/)
    end
    
    it "raises error when headers response is not valid JSON" do
      ENV["MORPH_AUSTRALIAN_PROXY"] = "http://test.proxy:8888"
      config = described_class.new(australian_proxy: true)
      
      # Stub valid IP but invalid JSON for headers
      stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
        .to_return(body: "1.2.3.4")
      stub_request(:get, ScraperUtils::MechanizeUtils::HEADERS_ECHO_URL)
        .to_return(body: "not-valid-json")
      
      # This should output a warning but not raise an error
      expect {
        config.send(:verify_proxy_works, agent)
      }.not_to raise_error
    end
    
    it "succeeds with valid IP and JSON headers response" do
      ENV["MORPH_AUSTRALIAN_PROXY"] = "http://test.proxy:8888"
      config = described_class.new(australian_proxy: true)
      
      # Stub valid responses
      stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
        .to_return(body: "1.2.3.4")
      stub_request(:get, ScraperUtils::MechanizeUtils::HEADERS_ECHO_URL)
        .to_return(body: '{"headers":{"User-Agent":"TestAgent"}}')
      
      expect {
        config.send(:verify_proxy_works, agent)
      }.not_to raise_error
    end
  end
end
