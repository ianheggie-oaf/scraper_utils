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

    context "with invalid info_url" do
      it "raises an error for a non-http scheme" do
        record = valid_record.merge("info_url" => "ftp://example.com")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /info_url must be a valid http\/https URL/)
      end

      it "raises an error for a URL without a host" do
        record = valid_record.merge("info_url" => "https://")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /info_url must be a valid http\/https URL/)
      end

      it "raises an error for a plain string" do
        record = valid_record.merge("info_url" => "not-a-url")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /info_url must be a valid http\/https URL/)
      end

      it "accepts a valid https URL" do
        record = valid_record.merge("info_url" => "https://council.gov.au/app?id=123")
        expect(ScraperWiki).to receive(:save_sqlite).with(["council_reference"], record)
        expect(ScraperUtils::DataQualityMonitor).to receive(:log_saved_record).with(record)
        described_class.save_record(record)
      end
    end

    context "with invalid date formats" do
      it "raises an error for non-ISO date_scraped" do
        record = valid_record.merge("date_scraped" => "23 Aug 2024")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /Invalid date format/)
      end

      it "raises an error for invalid date_scraped" do
        record = valid_record.merge("date_scraped" => "invalid-date")
        expect do
          described_class.save_record(record)
        end.to raise_error(ScraperUtils::UnprocessableRecord, /Invalid date format/)
      end

      it "raises an error for non-ISO date_received" do
        record = valid_record.merge("date_received" => "23/08/2024")
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

      it "accepts Date objects for date fields" do
        record = valid_record.merge("date_received" => Date.today)
        expect(ScraperWiki).to receive(:save_sqlite).with(["council_reference"], record)
        expect(ScraperUtils::DataQualityMonitor).to receive(:log_saved_record).with(record)
        described_class.save_record(record)
      end

      it "accepts DateTime objects for date fields" do
        record = valid_record.merge("date_received" => DateTime.now)
        expect(ScraperWiki).to receive(:save_sqlite).with(["council_reference"], record)
        expect(ScraperUtils::DataQualityMonitor).to receive(:log_saved_record).with(record)
        described_class.save_record(record)
      end

      it "accepts Time objects for date fields" do
        record = valid_record.merge("date_received" => Time.now)
        expect(ScraperWiki).to receive(:save_sqlite).with(["council_reference"], record)
        expect(ScraperUtils::DataQualityMonitor).to receive(:log_saved_record).with(record)
        described_class.save_record(record)
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

  describe ".cleanup_old_records" do
    let(:db_file) { "data.sqlite" }

    before do
      clobber_db

      # Create the database and table structure with current records
      3.times do |age|
        ScraperWiki.save_sqlite(["council_reference"], valid_record(age: age))
      end
    end

    after do
      clobber_db
    end

    context "when there are no old records" do
      it "does not delete any records" do
        expect { described_class.cleanup_old_records }.not_to(change do
          ScraperWiki.sqliteexecute("SELECT COUNT(*) as count FROM data").first["count"]
        end)
      end

      it "does not run VACUUM" do
        allow(ScraperWiki).to receive(:sqliteexecute).and_call_original
        described_class.cleanup_old_records
        expect(ScraperWiki).not_to have_received(:sqliteexecute).with("VACUUM")
      end
    end

    context "when there are old records" do
      before do
        # Add old records (older than 30 days)
        2.times do |age|
          ScraperWiki.save_sqlite(["council_reference"], valid_record(age: 31 + age))
        end
      end

      it "deletes records older than 30 days" do
        expect do
          described_class.cleanup_old_records
        end.to change {
          ScraperWiki.sqliteexecute("SELECT COUNT(*) as count FROM data").first["count"]
        }.from(5).to(3)
      end

      it "keeps recent records" do
        described_class.cleanup_old_records
        remaining = ScraperWiki.sqliteexecute("SELECT council_reference FROM data ORDER BY council_reference")
        expect(remaining.map { |r| r["council_reference"] }).to eq(%w[DA100 DA101 DA102])
      end

      it "logs the deletion" do
        allow(ScraperUtils::LogUtils).to receive(:log)
        described_class.cleanup_old_records
        expect(ScraperUtils::LogUtils).to have_received(:log).with(a_string_matching(/Deleting 2 applications/))
      end
    end

    context "when VACUUM should run" do
      before do
        # Add very old records (older than 35 days)
        ScraperWiki.save_sqlite(["council_reference"], valid_record(age: 40))
      end

      it "runs VACUUM when oldest record is older than 35 days" do
        allow(ScraperUtils::LogUtils).to receive(:log)
        allow(ScraperWiki).to receive(:sqliteexecute).and_call_original

        described_class.cleanup_old_records

        expect(ScraperWiki).to have_received(:sqliteexecute).with("VACUUM")
        expect(ScraperUtils::LogUtils).to have_received(:log).with(a_string_matching(/Running VACUUM/))
      end
    end

    context "when ENV['VACUUM'] is set" do
      before do
        ENV["VACUUM"] = "true"
      end

      after do
        ENV.delete("VACUUM")
      end

      it "runs VACUUM even with no old records when ENV['VACUUM'] is set" do
        allow(ScraperWiki).to receive(:sqliteexecute).and_call_original
        described_class.cleanup_old_records
        expect(ScraperWiki).to have_received(:sqliteexecute).with("VACUUM")
      end
    end

    context "with edge case dates" do
      it "does not delete records exactly 30 days old" do
        ScraperWiki.save_sqlite(["council_reference"], valid_record(age: 30))

        described_class.cleanup_old_records

        result = ScraperWiki.sqliteexecute("SELECT COUNT(*) as count FROM data").first
        expect(result["count"]).to eq(4)
      end

      it "deletes records 31 days old" do
        ScraperWiki.save_sqlite(["council_reference"], valid_record(age: 31))

        described_class.cleanup_old_records

        result = ScraperWiki.sqliteexecute("SELECT COUNT(*) as count FROM data").first
        expect(result["count"]).to eq(3)
      end
    end
  end

  private

  def clobber_db
    return unless File.exist?(db_file)

    ScraperWiki.close_sqlite
    File.delete(db_file)
  end

  def valid_record(age: 0)
    {
      "council_reference" => "DA#{100 + age}",
      "address" => "#{100 + age} Test St, Testville",
      "description" => "Test development for #{age} days old application",
      "info_url" => "https://example.com",
      "date_scraped" => (Date.today - age).to_s
    }
  end
end
