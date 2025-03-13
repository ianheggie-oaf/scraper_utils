# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::MechanizeUtils do
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
