# frozen_string_literal: true

require_relative "../spec_helper"
require "date"

RSpec.describe ScraperUtils::DbUtils do
  # Ensure clean state before each test
  before do
    described_class.save_immediately!
  end

  describe ".save_record" do
    let(:valid_record) do
      {
        "council_reference" => "DA123",
        "address" => "123 Test St, Testville",
        "description" => "Test development",
        "info_url" => "https://example.com",
        "date_scraped" => Date.today.to_s
      }
    end

    context "in immediate save mode (default)" do
      it "saves a valid record" do
        expect(ScraperWiki).to receive(:save_sqlite).with(["council_reference"], valid_record)
        expect(ScraperUtils::DataQualityMonitor).to receive(:log_saved_record).with(valid_record)
        described_class.save_record(valid_record)
      end

      context "with optional date fields" do
        it "validates date_received" do
          record = valid_record.merge("date_received" => Date.today.to_s)
          expect(ScraperWiki).to receive(:save_sqlite).with(["council_reference"], record)
          expect(ScraperUtils::DataQualityMonitor).to receive(:log_saved_record).with(record)
          described_class.save_record(record)
        end

        it "validates on_notice_from" do
          record = valid_record.merge("on_notice_from" => Date.today.to_s)
          expect(ScraperWiki).to receive(:save_sqlite).with(["council_reference"], record)
          expect(ScraperUtils::DataQualityMonitor).to receive(:log_saved_record).with(record)
          described_class.save_record(record)
        end

        it "validates on_notice_to" do
          record = valid_record.merge("on_notice_to" => Date.today.to_s)
          expect(ScraperWiki).to receive(:save_sqlite).with(["council_reference"], record)
          expect(ScraperUtils::DataQualityMonitor).to receive(:log_saved_record).with(record)
          described_class.save_record(record)
        end
      end

      context "with authority_label" do
        it "uses authority_label in primary key" do
          record = valid_record.merge("authority_label" => "test_council")
          expect(ScraperWiki).to receive(:save_sqlite).with(%w[authority_label council_reference], record)
          expect(ScraperUtils::DataQualityMonitor).to receive(:log_saved_record).with(record)
          described_class.save_record(record)
        end
      end
    end

    context "in collection mode" do
      before do
        described_class.collect_saves!
      end

      it "collects records instead of saving immediately" do
        expect(ScraperWiki).not_to receive(:save_sqlite)
        expect(ScraperUtils::DataQualityMonitor).not_to receive(:log_saved_record)

        described_class.save_record(valid_record)

        expect(described_class.collected_saves).to eq([valid_record])
      end

      it "collects multiple records" do
        record2 = valid_record.merge("council_reference" => "DA456")

        described_class.save_record(valid_record)
        described_class.save_record(record2)

        expect(described_class.collected_saves).to eq([valid_record, record2])
      end

      it "still validates records in collection mode" do
        invalid_record = valid_record.merge("council_reference" => "")

        expect do
          described_class.save_record(invalid_record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /council_reference/)
      end

      context "switching back to immediate mode" do
        it "resumes saving immediately after save_immediately!" do
          described_class.save_record(valid_record)
          expect(described_class.collected_saves).to eq([valid_record])

          described_class.save_immediately!

          expect(ScraperWiki).to receive(:save_sqlite).with(["council_reference"], valid_record)
          expect(ScraperUtils::DataQualityMonitor).to receive(:log_saved_record).with(valid_record)
          described_class.save_record(valid_record)
        end
      end
    end

    context "with missing required fields" do
      it "raises an error for missing council_reference" do
        record = valid_record.merge("council_reference" => "")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /council_reference/)
      end

      it "raises an error for missing address" do
        record = valid_record.merge("address" => "")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /address/)
      end

      it "raises an error for missing description" do
        record = valid_record.merge("description" => "")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /description/)
      end

      it "raises an error for missing info_url" do
        record = valid_record.merge("info_url" => "")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /info_url/)
      end

      it "raises an error for missing date_scraped" do
        record = valid_record.merge("date_scraped" => "")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /date_scraped/)
      end
    end

    context "with invalid date formats" do
      it "raises an error for invalid date_scraped" do
        record = valid_record.merge("date_scraped" => "invalid-date")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /Invalid date format/)
      end

      it "raises an error for invalid date_received" do
        record = valid_record.merge("date_received" => "invalid-date")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /Invalid date format/)
      end

      it "raises an error for invalid on_notice_from" do
        record = valid_record.merge("on_notice_from" => "invalid-date")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /Invalid date format/)
      end

      it "raises an error for invalid on_notice_to" do
        record = valid_record.merge("on_notice_to" => "invalid-date")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /Invalid date format/)
      end
    end
  end

  describe ".collect_saves!" do
    it "enables collection mode" do
      described_class.collect_saves!
      expect(described_class.collected_saves).to eq([])
    end

    it "clears any existing collected saves" do
      described_class.collect_saves!
      described_class.save_record(valid_record)

      described_class.collect_saves!
      expect(described_class.collected_saves).to eq([])
    end
  end

  describe ".save_immediately!" do
    it "disables collection mode" do
      described_class.collect_saves!
      described_class.save_immediately!
      expect(described_class.collected_saves).to be_nil
    end
  end

  describe ".collected_saves" do
    context "when not in collection mode" do
      it "returns nil" do
        expect(described_class.collected_saves).to be_nil
      end
    end

    context "when in collection mode" do
      before do
        described_class.collect_saves!
      end

      it "returns empty array initially" do
        expect(described_class.collected_saves).to eq([])
      end

      it "returns collected records" do
        described_class.save_record(valid_record)
        expect(described_class.collected_saves).to eq([valid_record])
      end
    end
  end

  private

  def valid_record
    {
      "council_reference" => "DA123",
      "address" => "123 Test St, Testville",
      "description" => "Test development",
      "info_url" => "https://example.com",
      "date_scraped" => Date.today.to_s
    }
  end
end
