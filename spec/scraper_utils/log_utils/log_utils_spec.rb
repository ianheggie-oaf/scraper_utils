# frozen_string_literal: true

require_relative "../../spec_helper"
require "date"

RSpec.describe ScraperUtils::LogUtils do
  describe ".log" do
    it "logs a message to stdout with authority prefix when provided" do
      authority = :test_authority
      message = "Test message"
      
      expect {
        described_class.log(message, authority)
      }.to output(/\[#{authority}\] #{message}/).to_stdout
    end
    
    it "logs a message to stdout without prefix when authority is nil" do
      message = "Test message without prefix"
      
      expect {
        described_class.log(message)
      }.to output(/#{message}/).to_stdout
      
      # Should not have any square brackets
      expect {
        described_class.log(message)
      }.not_to output(/\[.*\]/).to_stdout
    end
    
    it "uses Scheduler.current_authority when no authority provided" do
      authority = :current_authority
      ENV['AUTHORITY'] = authority.to_s
      message = "Test message with current authority"

      expect {
        described_class.log(message)
      }.to output(/\[#{authority}\] #{message}/).to_stdout
    ensure
      ENV['AUTHORITY'] = nil
    end
  end

  describe ".log_scraping_run" do
    let(:run_at) { Time.now - 123 }
    let(:interrupted_and_broken_exceptions) do
      {
        interrupted_council: StandardError.new("Part way through error"),
        broken_council: StandardError.new("It is BROKEN error")
      }
    end
    let(:four_authorities) { %i[good_council interrupted_council broken_council empty_council] }
    let(:four_stats) do
      {
        good_council: { saved: 10, unprocessed: 0 },
        interrupted_council: { saved: 5, unprocessed: 0 },
        broken_council: { saved: 0, unprocessed: 7 },
        empty_council: { saved: 0, unprocessed: 0 }
      }
    end

    # Mock DataQualityMonitor stats
    before do
      allow(ScraperUtils::DataQualityMonitor).to receive(:stats).and_return(four_stats)
    end

    it "logs scraping run for multiple authorities" do
      # Define the common parameters used in all expectations
      common_params = {
        "attempt" => 1,
        "error_backtrace" => nil,
        "run_at" => run_at.iso8601,
        "unprocessable_records" => 0,
        "error_class" => nil,
        "error_message" => nil,
        "records_saved" => 0,
        "status" => "failed"
      }

      expect(ScraperWiki).to receive(:save_sqlite)
        .with(%w[authority_label run_at],
              hash_including(common_params.merge(
                               "authority_label" => "good_council",
                               "records_saved" => 10,
                               "status" => "successful"
                             )),
              ScraperUtils::LogUtils::LOG_TABLE)
        .once
      expect(ScraperWiki).to receive(:save_sqlite)
        .with(%w[authority_label run_at],
              hash_including(common_params.merge(
                               "authority_label" => "interrupted_council",
                               "error_class" => "StandardError",
                               "error_message" => "Part way through error",
                               "records_saved" => 5,
                               "status" => "interrupted"
                             )),
              ScraperUtils::LogUtils::LOG_TABLE)
        .once
      expect(ScraperWiki).to receive(:save_sqlite)
        .with(%w[authority_label run_at],
              hash_including(common_params.merge(
                               "authority_label" => "broken_council",
                               "error_class" => "StandardError",
                               "error_message" => "It is BROKEN error",
                               "unprocessable_records" => 7
                             )),
              ScraperUtils::LogUtils::LOG_TABLE)
        .once
      expect(ScraperWiki).to receive(:save_sqlite)
        .with(%w[authority_label run_at],
              hash_including(common_params.merge(
                               "authority_label" => "empty_council"
                             )),
              ScraperUtils::LogUtils::LOG_TABLE)
        .once
      expect(ScraperWiki).to receive(:save_sqlite)
        .with(["run_at"],
              hash_including(
                "attempt" => 1,
                "duration" => 123.0,
                "failed" => "broken_council,empty_council",
                "failed_count" => 2,
                "interrupted" => "interrupted_council",
                "interrupted_count" => 1,
                "run_at" => run_at.iso8601,
                "successful" => "good_council",
                "successful_count" => 1
              ),
              ScraperUtils::LogUtils::SUMMARY_TABLE)
        .once

      described_class.log_scraping_run(run_at, 1, four_authorities,
                                       interrupted_and_broken_exceptions)
    end

    it "raises error for invalid start time" do
      deliberately_not_time = "not a time object"
      expect do
        # noinspection RubyMismatchedArgumentType
        described_class.log_scraping_run(deliberately_not_time, 1, four_authorities,
                                         interrupted_and_broken_exceptions)
      end.to raise_error(ArgumentError, "Invalid start time")
    end

    it "raises error for empty authorities" do
      expect do
        described_class.log_scraping_run(run_at, 1, [], interrupted_and_broken_exceptions)
      end.to raise_error(ArgumentError, "Authorities must be a non-empty array")
    end

    it "handles authorities with no results" do
      common_params = { "attempt" => 1,
                        "error_backtrace" => nil,
                        "error_class" => nil,
                        "error_message" => nil,
                        "records_saved" => 0,
                        "run_at" => run_at.iso8601,
                        "status" => "failed",
                        "unprocessable_records" => 0 }
      expect(ScraperWiki).to receive(:save_sqlite)
        .with(%w[authority_label run_at],
              hash_including(common_params.merge(
                               "authority_label" => "good_council",
                               "records_saved" => 10,
                               "run_at" => run_at.iso8601,
                               "status" => "successful"
                             )),
              ScraperUtils::LogUtils::LOG_TABLE)
        .once
      expect(ScraperWiki).to receive(:save_sqlite)
        .with(%w[authority_label run_at],
              hash_including(common_params.merge(
                               "authority_label" => "interrupted_council",
                               "error_class" => "StandardError",
                               "error_message" => "Part way through error",
                               "records_saved" => 5,
                               "status" => "interrupted"
                             )),
              ScraperUtils::LogUtils::LOG_TABLE)
        .once
      expect(ScraperWiki).to receive(:save_sqlite)
        .with(%w[authority_label run_at],
              hash_including(common_params.merge(
                               "authority_label" => "broken_council",
                               "error_class" => "StandardError",
                               "error_message" => "It is BROKEN error",
                               "unprocessable_records" => 7
                             )),
              ScraperUtils::LogUtils::LOG_TABLE)
        .once
      expect(ScraperWiki).to receive(:save_sqlite)
        .with(%w[authority_label run_at],
              hash_including(common_params.merge(
                               "authority_label" => "empty_council"
                             )),
              ScraperUtils::LogUtils::LOG_TABLE)
        .once

      expect(ScraperWiki)
        .to receive(:save_sqlite)
        .with(["run_at"],
              hash_including(
                "duration" => 123.0,
                "attempt" => 1,
                "failed" => "broken_council,empty_council",
                "failed_count" => 2,
                "interrupted" => "interrupted_council",
                "interrupted_count" => 1,
                "public_ip" => nil,
                "run_at" => run_at.iso8601,
                "successful" => "good_council",
                "successful_count" => 1
              ),
              ScraperUtils::LogUtils::SUMMARY_TABLE)
        .once

      described_class.log_scraping_run(run_at, 1, four_authorities,
                                       interrupted_and_broken_exceptions)
    end

    it "tracks summary of different authority statuses" do
      summary_record = nil

      # Capture the summary record when it's saved
      allow(ScraperWiki).to receive(:save_sqlite) do |_keys, record, table|
        summary_record = record if table == ScraperUtils::LogUtils::SUMMARY_TABLE
      end

      described_class.log_scraping_run(run_at, 1, four_authorities,
                                       interrupted_and_broken_exceptions)

      expect(summary_record).not_to be_nil
      expect(summary_record["successful"]).to include("good_council")
      expect(summary_record["interrupted"]).to include("interrupted_council")
      expect(summary_record["failed"]).to include("broken_council,empty_council")
    end

    it "performs periodic record cleanup" do
      expect(described_class).to receive(:cleanup_old_records).once

      described_class.log_scraping_run(run_at, 1, four_authorities,
                                       interrupted_and_broken_exceptions)
    end
  end
end
