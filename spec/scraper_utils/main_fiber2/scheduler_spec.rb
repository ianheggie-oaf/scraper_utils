# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe ScraperUtils::Scheduler do
  let(:operation_registry) { described_class.send(:operation_registry) }
  let(:operations) { operation_registry.instance_variable_get(:@operations) }

  before do
    described_class.reset!
  end

  describe ".threaded" do
    it "defaults to true" do
      expect(described_class.threaded).to be true
    end

    it "has question form" do
      expect(described_class.threaded?).to be true
    end

    it "can be set" do
      described_class.threaded = false
      expect(described_class.threaded?).to be false
    end

    it "Is disabled by MORPH_DISABLE_THREADS ENV variable" do
      expect(described_class.threaded?).to be true
      ENV['MORPH_DISABLE_THREADS'] = '42'
      described_class.reset!
      expect(described_class.threaded?).to be false
    ensure
      ENV['MORPH_DISABLE_THREADS'] = nil
    end
  end

  describe ".max_workers" do
    it "defaults to DEFAULT_MAX_WORKERS" do
      expect(described_class.max_workers).to be ScraperUtils::Scheduler::Constants::DEFAULT_MAX_WORKERS
    end

    it "can be set" do
      described_class.max_workers = 11
      expect(described_class.max_workers).to be 11
    end

    it "Is set by MORPH_MAX_WORKERS ENV variable" do
      ENV['MORPH_MAX_WORKERS'] = '42'
      described_class.reset!
      expect(described_class.max_workers).to be 42
    ensure
      ENV['MORPH_MAX_WORKERS'] = nil
    end
  end

  describe ".exceptions" do
    it "defaults to empty Hash" do
      expect(described_class.exceptions).to eq Hash.new
    end
  end

  describe ".timeout" do
    it "defaults to DEFAULT_TIMEOUT" do
      expect(described_class.timeout).to be ScraperUtils::Scheduler::Constants::DEFAULT_TIMEOUT
    end

    it "Is set by MORPH_TIMEOUT ENV variable" do
      ENV['MORPH_TIMEOUT'] = '42'
      described_class.reset!
      expect(described_class.timeout).to be 42
    ensure
      ENV['MORPH_TIMEOUT'] = nil
    end
  end

  describe ".reset!" do
    it "Sets defaults" do
      expect(described_class.send(:exceptions)).to be_a(Hash)
      expect(described_class.send(:totals)[:delay_requested]).to be 0
      expect(described_class.send(:totals)[:poll_sleep]).to be 0
      expect(described_class.send(:totals)[:resume_count]).to be 0
      expect(described_class.send(:initial_resume_at)).to be_a(Time)
      expect(described_class.send(:response_queue)).to be_a(Thread::Queue)
      expect(described_class.send(:operation_registry)).to be_a(ScraperUtils::Scheduler::OperationRegistry)
      expect(described_class.send(:reset)).to be true
    end
  end
end
