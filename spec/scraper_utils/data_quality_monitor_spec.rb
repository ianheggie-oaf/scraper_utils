# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::DataQualityMonitor do
  describe ".start_authority" do
    it "initializes stats for a new authority" do
      described_class.start_authority(:test_authority)
      expect(described_class.instance_variable_get(:@stats)[:test_authority])
        .to eq(saved: 0, unprocessed: 0)
    end

    it "resets stats when called multiple times" do
      described_class.start_authority(:first_authority)
      described_class.start_authority(:second_authority)
      expect(described_class.instance_variable_get(:@stats)[:second_authority])
        .to eq(saved: 0, unprocessed: 0)
    end
  end

  describe ".log_unprocessable_record" do
    before do
      described_class.start_authority(:test_authority)
    end

    it "increments unprocessed record count" do
      error = StandardError.new("Test error")
      record = { "address" => "123 Test St", "authority_label" => "test_authority" }

      expect { described_class.log_unprocessable_record(error, record) }
        .to change { described_class.instance_variable_get(:@stats)[:test_authority][:unprocessed] }
        .by(1)
    end

    it "raises UnprocessableSite when error threshold is exceeded" do
      error = StandardError.new("Test error")
      record = { "address" => "123 Test St", "authority_label" => "test_authority" }

      # Log 5 unprocessable records when only 0 saved (threshold is 5)
      5.times do
        described_class.log_unprocessable_record(error, record)
      end

      expect { described_class.log_unprocessable_record(error, record) }
        .to raise_error(ScraperUtils::UnprocessableSite, /Too many unprocessable_records/)
    end

    it "allows more unprocessable records proportional to saved records" do
      error = ScraperUtils::UnprocessableRecord.new("Test error")
      record = { "address" => "123 Test St", "authority_label" => "test_authority" }

      # Log 10 saved records
      10.times do
        described_class.log_saved_record(record)
      end

      # Should now allow up to 6 unprocessable records (5 + 10%)
      expect do
        6.times do
          described_class.log_unprocessable_record(error, record)
        end
      end.not_to raise_error

      expect(described_class.threshold(:test_authority)).to be_within(0.01).of(6.0)
      # 6th unprocessable record should raise an error (6 is > 5 + 10 * 10%)
      expect { described_class.log_unprocessable_record(error, record) }
        .to raise_error(ScraperUtils::UnprocessableSite)
    end
  end

  describe ".log_saved_record" do
    before do
      described_class.start_authority(:test_authority)
    end

    it "increments saved record count" do
      record = { "address" => "123 Test St", "authority_label" => "test_authority" }

      expect { described_class.log_saved_record(record) }
        .to change { described_class.instance_variable_get(:@stats)[:test_authority][:saved] }
        .by(1)
    end
  end
end
