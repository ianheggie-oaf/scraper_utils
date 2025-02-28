# frozen_string_literal: true

require_relative "../spec_helper"
require "date"

RSpec.describe ScraperUtils::LogUtils do
  let(:interrupted_and_broken_exceptions) do
    {
      interrupted_council: StandardError.new("Part way through error"),
      broken_council: StandardError.new("It is BROKEN error")
    }
  end

  let(:empty_exceptions) do
    {}
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

  describe ".log_scraping_run" do
    let(:run_at) { Time.now - 123 }

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

    it "performs cleanup_old_records once per day" do
      [
        ScraperUtils::LogUtils::SUMMARY_TABLE,
        ScraperUtils::LogUtils::LOG_TABLE
      ].each do |table|
        expect(ScraperWiki)
          .to receive(:sqliteexecute)
          .with("DELETE FROM #{table} WHERE date(run_at) < date(?)", [be_a(String)])
          .once
      end
      described_class.cleanup_old_records(force: true)
      described_class.cleanup_old_records
    end

    context "with a complex backtrace" do
      let(:complex_error) do
        error = StandardError.new("Test error")
        error.set_backtrace(
          [
            # Ruby/gem internal lines (should be limited to 3)
            "/app/vendor/ruby-3.2.2/lib/ruby/3.2.0/net/http.rb:1271:in `initialize'",
            "/app/vendor/ruby-3.2.2/lib/ruby/3.2.0/net/http.rb:1272:in `open'",
            "/app/vendor/ruby-3.2.2/lib/ruby/3.2.0/net/http.rb:1273:in `start'",
            "/app/vendor/bundle/ruby/3.2.0/gems/n.../net/http/persistent.rb:711:in `start'",
            "/app/vendor/bundle/ruby/3.2.0/gems/n.../http/persistent.rb:641:in `connection_for'",
            "/app/vendor/bundle/ruby/3.2.0/gems/n.../net/http/persistent.rb:941:in `request'",
            "/app/vendor/bundle/ruby/3.2.0/gems/m.../mechanize/http/agent.rb:284:in `fetch'",

            # Application-specific lines
            "/app/lib/masterview_scraper/authority_scraper.rb:59:in `scrape_api_period'",
            "/app/lib/masterview_scraper/authority_scraper.rb:30:in `scrape_period'",
            "/app/lib/masterview_scraper/authority_scraper.rb:9:in `scrape'",
            "/app/lib/masterview_scraper/authority_scraper.rb:42:in `main'"
          ]
        )
        error
      end

      it "removes Ruby and gem internal traces and limits total lines" do
        log_record = nil

        # Capture the log record when it's saved
        allow(ScraperWiki).to receive(:save_sqlite) do |_keys, record, table|
          if table == ScraperUtils::LogUtils::LOG_TABLE
            puts "ZZZ record: #{record.inspect}"
            log_record = record
          end
        end

        described_class.log_scraping_run(run_at, 1, [:complex_council],
                                         { complex_council: complex_error })

        expect(log_record).not_to be_nil

        trace = log_record["error_backtrace"] || ""
        trace_lines = trace.split("\n")

        # Check total number of lines is limited to 6
        expect(trace_lines.length).to be <= 6

        # Check application-specific lines are present
        expect(trace).to include("authority_scraper.rb:59:in `scrape_api_period'")
        expect(trace).to include("authority_scraper.rb:30:in `scrape_period'")
        expect(trace).to include("authority_scraper.rb:9:in `scrape'")
        expect(trace).to include("authority_scraper.rb:42:in `main'")

        # Verify that vendor/Ruby lines are limited
        vendor_lines = trace_lines.select { |line| line.include?("/vendor/") }
        expect(vendor_lines.length).to be <= 3
      end
    end
  end

  describe ".extract_meaningful_backtrace" do
    context "with a complex backtrace" do
      let(:error) do
        error = StandardError.new("Test error")
        error.set_backtrace(
          [
            "/app/vendor/ruby-3.2.2/lib/ruby/3.2.0/net/http.rb:1271:in `initialize'",
            "/app/vendor/ruby-3.2.2/lib/ruby/3.2.0/net/http.rb:1271:in `open'",
            "/app/vendor/bundle/ruby/3.2.0/gems/m.../lib/m.../http/agent.rb:284:in `fetch'",
            "/app/lib/masterview_scraper/authority_scraper.rb:59:in `scrape_api_period'",
            "/app/lib/masterview_scraper/authority_scraper.rb:30:in `scrape_period'",
            "/app/lib/masterview_scraper/authority_scraper.rb:9:in `scrape'",
            "/app/lib/masterview_scraper/authority_scraper.rb:42:in `main'"
          ]
        )
        error
      end

      it "removes Ruby and gem internal traces" do
        meaningful_trace = described_class.extract_meaningful_backtrace(error)

        expect(meaningful_trace).to include("authority_scraper.rb:59:in `scrape_api_period'")
        expect(meaningful_trace).to include("authority_scraper.rb:30:in `scrape_period'")
        expect(meaningful_trace).to include("authority_scraper.rb:9:in `scrape'")
        expect(meaningful_trace).to include("authority_scraper.rb:42:in `main'")
      end
    end

    context "with a nil error" do
      it "returns nil" do
        expect(described_class.extract_meaningful_backtrace(nil)).to be_nil
      end
    end

    context "with an error without backtrace" do
      it "returns nil" do
        error = StandardError.new("Test error")
        error.set_backtrace(nil)

        expect(described_class.extract_meaningful_backtrace(error)).to be_nil
      end
    end
  end

  describe ".report_on_results" do
    before do
      # Mock DataQualityMonitor stats for broken_council
      allow(ScraperUtils::DataQualityMonitor).to receive(:stats).and_return(four_stats)
    end

    context "when all authorities work as expected" do
      it "exits with OK status when no unexpected conditions" do
        ENV["MORPH_EXPECT_BAD"] = "broken_council"

        expect { described_class.report_on_results(four_authorities, empty_exceptions) }
          .to output(/Exiting with OK status!/).to_stdout

        ENV["MORPH_EXPECT_BAD"] = nil
      end
    end

    context "when an expected bad authority starts working" do
      it "raises an error with a warning about removing from EXPECT_BAD" do
        ENV["MORPH_EXPECT_BAD"] = "interrupted_council"

        expect { described_class.report_on_results(four_authorities, empty_exceptions) }
          .to raise_error(RuntimeError, /WARNING: Remove interrupted_council from MORPH_EXPECT_BAD/)

        ENV["MORPH_EXPECT_BAD"] = nil
      end
    end

    context "when an unexpected error occurs" do
      after do
        ENV["MORPH_EXPECT_BAD"] = nil
      end

      it "includes errors in summary" do
        ENV["MORPH_EXPECT_BAD"] = "broken_council"

        expect do
          described_class.report_on_results(four_authorities, interrupted_and_broken_exceptions)
        end
          .to raise_error(RuntimeError, /ERROR: Unexpected errors/)
          .and output(/interrupted_council {7}5 {6}0 StandardError - Part way through error/)
          .to_stdout

        expect do
          described_class.report_on_results(four_authorities, interrupted_and_broken_exceptions)
        end
          .to raise_error(RuntimeError, /ERROR: Unexpected errors/)
          .and output(/broken_council {12}0 {6}7 \[EXPECT BAD\] StandardError - It is BROKEN error/)
          .to_stdout
      end

      it "raises an error with details about unexpected errors" do
        ENV["MORPH_EXPECT_BAD"] = "broken_council"
        summary_has_error = "ERROR: Unexpected errors in: interrupted_council"
        error_details = "interrupted_council: StandardError - Part way through error"

        expect do
          described_class.report_on_results(four_authorities, interrupted_and_broken_exceptions)
        end
          .to raise_error(RuntimeError,
                          /#{Regexp.escape(summary_has_error)}.*#{Regexp.escape(error_details)}/m)
      end
    end

    context "with no MORPH_EXPECT_BAD set" do
      it "works without any environment variable" do
        expect { described_class.report_on_results(four_authorities, empty_exceptions) }
          .to output(/Exiting with OK status!/).to_stdout
      end
    end
  end
end
