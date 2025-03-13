# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::MechanizeUtils do
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
end
