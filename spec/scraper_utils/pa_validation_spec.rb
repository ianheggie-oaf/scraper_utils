# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::PaValidation do
  let(:valid_record) do
    {
      "council_reference" => "DA123",
      "address" => "123 Test St, Testville",
      "description" => "Test development",
      "info_url" => "https://example.com",
      "date_scraped" => Date.today.to_s
    }
  end

  describe ".validate_record" do
    it "returns nil for a valid record" do
      expect(described_class.validate_record(valid_record)).to be_nil
    end

    it "normalises symbol keys" do
      record = valid_record.transform_keys(&:to_sym)
      expect(described_class.validate_record(record)).to be_nil
    end

    context "with missing required fields" do
      %w[council_reference address description date_scraped].each do |field|
        it "returns error for blank #{field}" do
          errors = described_class.validate_record(valid_record.merge(field => ""))
          expect(errors).to include(/#{field}/)
        end
      end

      it "returns error for blank info_url" do
        errors = described_class.validate_record(valid_record.merge("info_url" => ""))
        expect(errors).to include(/info_url/)
      end
    end

    context "with invalid info_url" do
      it "returns error for non-http scheme" do
        errors = described_class.validate_record(valid_record.merge("info_url" => "ftp://example.com"))
        expect(errors).to include(/info_url/)
      end

      it "returns error for URL without host" do
        errors = described_class.validate_record(valid_record.merge("info_url" => "https://"))
        expect(errors).to include(/info_url/)
      end

      it "returns error for plain string" do
        errors = described_class.validate_record(valid_record.merge("info_url" => "not-a-url"))
        expect(errors).to include(/info_url/)
      end

      it "returns error for URL with spaces (triggers InvalidURIError)" do
        errors = described_class.validate_record(valid_record.merge("info_url" => "https://example .com/path"))
        expect(errors).to include(/info_url/)
      end
    end

    context "with invalid dates" do
      it "returns error for non-ISO date_scraped" do
        errors = described_class.validate_record(valid_record.merge("date_scraped" => "23 Aug 2024"))
        expect(errors).to include(/date_scraped/)
      end

      it "returns error for future date_received" do
        errors = described_class.validate_record(valid_record.merge("date_received" => (Date.today + 1).to_s))
        expect(errors).to include(/date_received/)
      end

      it "returns error for invalid on_notice_from" do
        errors = described_class.validate_record(valid_record.merge("on_notice_from" => "not-a-date"))
        expect(errors).to include(/on_notice_from/)
      end

      it "returns error for invalid on_notice_to" do
        errors = described_class.validate_record(valid_record.merge("on_notice_to" => "not-a-date"))
        expect(errors).to include(/on_notice_to/)
      end

      it "accepts Date objects" do
        expect(described_class.validate_record(valid_record.merge("date_received" => Date.today))).to be_nil
      end

      it "accepts Time objects" do
        expect(described_class.validate_record(valid_record.merge("date_received" => Time.now))).to be_nil
      end

      it "returns error for date string that passes format but is invalid (e.g. Feb 30)" do
        errors = described_class.validate_record(valid_record.merge("date_scraped" => "2024-02-30"))
        expect(errors).to include(/date_scraped/)
      end
    end

    it "returns multiple errors at once" do
      record = valid_record.merge("council_reference" => "", "address" => "")
      expect(described_class.validate_record(record).size).to be >= 2
    end
  end

  describe ".validate_record!" do
    it "does not raise for a valid record" do
      expect { described_class.validate_record!(valid_record) }.not_to raise_error
    end

    it "raises UnprocessableRecord for an invalid record" do
      record = valid_record.merge("council_reference" => "")
      expect { described_class.validate_record!(record) }
        .to raise_error(ScraperUtils::UnprocessableRecord, /council_reference/)
    end
  end


end
