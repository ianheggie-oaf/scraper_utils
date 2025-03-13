# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::LogUtils do
  describe ".log" do
    it "logs to stdout with authority prefix when provided" do
      expect { described_class.log("test message", :test_authority) }
        .to output(/\[test_authority\] test message/).to_stdout
    end
    
    it "uses the current authority when available" do
      allow(ScraperUtils::Scheduler).to receive(:current_authority).and_return(:current_authority)
      
      expect { described_class.log("test message") }
        .to output(/\[current_authority\] test message/).to_stdout
    end
  end
  
  # Basic test for log_scraping_run
  describe ".log_scraping_run" do
    before do
      allow(ScraperUtils::DataQualityMonitor).to receive(:stats).and_return({
        test_authority: { saved: 10, unprocessed: 0 }
      })
      allow(ScraperWiki).to receive(:save_sqlite)
    end
    
    it "logs scraping run details" do
      start_time = Time.now
      described_class.log_scraping_run(start_time, 1, [:test_authority], {})
      
      expect(ScraperWiki).to have_received(:save_sqlite).at_least(2).times
    end
  end
  
  # Include one report_on_results test
  describe ".report_on_results" do
    before do
      allow(ScraperUtils::DataQualityMonitor).to receive(:stats).and_return({
        test_authority: { saved: 10, unprocessed: 0 }
      })
    end
    
    it "produces a report with the authority results" do
      expect { described_class.report_on_results([:test_authority], {}) }
        .to output(/Scraping Summary:/).to_stdout
        .and output(/test_authority/).to_stdout
    end
  end
  
  # Add tests for the extracted methods
  describe ".cleanup_old_records" do
    it "cleans up records older than LOG_RETENTION_DAYS" do
      expect(ScraperWiki).to receive(:sqliteexecute).twice
      described_class.cleanup_old_records(force: true)
    end
  end
end

# Also require the detailed specs
require_relative "log_utils/basic_logging_spec"
require_relative "log_utils/reporting_spec"
