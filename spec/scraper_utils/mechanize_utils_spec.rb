# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::MechanizeUtils do
  describe ".mechanize_agent" do
    let(:page_content) { "<html><body>Test page</body></html>" }

    before do
      stub_request(:get, "https://example.com")
        .to_return(status: 200, body: page_content)
    end
  end

  describe ".mechanize_agent" do
    before do
      stub_request(:get, "https://example.com/robots.txt")
        .to_return(status: 200, body: "")
      stub_request(:get, "https://example.com")
        .to_return(status: 200, body: "<html><body>Test page</body></html>")
    end

    it "applies configured delays" do
      start_time = Time.now
      agent = described_class.mechanize_agent(
        max_load: 20.0,
        compliant_mode: true
      )
      agent.get("https://example.com")
      elapsed = Time.now - start_time
    end
  end

  describe ".find_maintenance_message" do
    context "with maintenance text" do
      before do
        stub_request(:get, "https://example.com/")
          .to_return(
            status: 200,
            body: "<html><h1>System Under Maintenance</h1></html>"
          )
      end

      it "detects maintenance in h1" do
        agent = Mechanize.new
        page = agent.get("https://example.com/")

        expect(described_class.find_maintenance_message(page))
          .to eq("Maintenance: System Under Maintenance")
      end
    end

    context "without maintenance text" do
      before do
        stub_request(:get, "https://example.com/")
          .to_return(
            status: 200,
            body: "<html><h1>Normal Page</h1></html>"
          )
      end

      it "returns nil" do
        agent = Mechanize.new
        page = agent.get("https://example.com/")

        expect(described_class.find_maintenance_message(page)).to be_nil
      end
    end
  end

  describe ".public_ip" do
    before do
      stub_request(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL)
        .to_return(body: "1.2.3.4\n")
    end

    it "retrieves the public IP" do
      agent = Mechanize.new

      expect(described_class.public_ip(agent, force: true))
        .to eq("1.2.3.4")
    end

    it "caches the IP address" do
      agent = Mechanize.new

      first_ip = described_class.public_ip(agent, force: true)
      expect(first_ip).to eq("1.2.3.4")

      second_ip = described_class.public_ip(agent)
      expect(second_ip).to eq("1.2.3.4")

      expect(WebMock).to have_requested(:get, ScraperUtils::MechanizeUtils::PUBLIC_IP_URL).once
    end
  end

  describe ".using_proxy?" do
    let(:agent) { Mechanize.new }

    context "when proxy is set" do
      before do
        agent.agent.set_proxy("http://test.proxy:8888")
      end

      it "returns true" do
        expect(described_class.using_proxy?(agent)).to be true
      end
    end

    context "when no proxy is set" do
      it "returns false" do
        expect(described_class.using_proxy?(agent)).to be false
      end
    end
  end

end
