# frozen_string_literal: true

require_relative '../spec_helper'
require 'date'
require 'terminal-table'

RSpec.describe ScraperUtils::DateRangeUtils do
  let(:utils) { described_class.new }

  before(:each) do
    described_class.reset_defaults!
  end

  describe ".configure" do
    it "allows configuring default values" do
      described_class.configure do |config|
        config.default_days = 45
        config.default_everytime = 4
        config.default_max_period = 5
      end

      expect(described_class.default_days).to eq(45)
      expect(described_class.default_everytime).to eq(4)
      expect(described_class.default_max_period).to eq(5)
    end
  end

  describe "#calculate_date_ranges" do
    let(:today) { Date.new(2025, 3, 1) }

    context "with basic parameters" do
      it "returns empty array when max_period is not positive" do
        expect(utils.calculate_date_ranges(max_period: 0, today: today)).to eq([])
      end

      it "returns empty array when days is not positive" do
        expect(utils.calculate_date_ranges(days: 0, today: today)).to eq([])
      end

      it "returns a single range when max_period is 1" do
        result = utils.calculate_date_ranges(days: 10, max_period: 1, today: today)
        expect(result).to eq([[today - 9, today, "everything"]])
      end

      it "returns a single range when everytime covers all days" do
        result = utils.calculate_date_ranges(days: 5, everytime: 5, today: today)
        expect(result).to eq([[today - 4, today, "everything"]])
      end
    end

    context "with fibonacci progression" do
      it "respects and uses max_period" do
        utils.calculate_date_ranges(days: 30, everytime: 2, max_period: 5, today: today)

        expect(utils.max_period_used).to eq(5)
      end
    end

    context "simulation testing" do
      it "provides good coverage with realistic parameters for max 2 days", :aggregate_failures do
        # Run a 60-day simulation to ensure all days get checked
        stats = DateRangeSimulator.run_simulation(
          utils,
          days: ScraperUtils::DateRangeUtils.default_days,
          everytime: ScraperUtils::DateRangeUtils.default_everytime,
          max_period: 2,
          visualize: !ENV['VISUALIZE']&.empty?
        )

        # Output the stats table
        puts stats[:table]

        # Basic verification of the algorithm properties
        expect(utils.max_period_used).to eq(2)
        expect(stats[:max_unchecked_streak]).to be <= 2
        expect(stats[:coverage_percentage]).to eq(100)

        # Verify load distribution
        avg = 42.4
        expect(stats[:avg_checked_per_day]).to be_between(avg - 1, avg + 1)
        expect(stats[:min_checked_per_day]).to be_between(avg - 1, avg + 1)
        expect(stats[:max_checked_per_day]).to be_between(avg - 1, avg + 1)
      end

      it "provides good coverage with realistic parameters for max 3 days", :aggregate_failures do
        # Run a 60-day simulation to ensure all days get checked
        stats = DateRangeSimulator.run_simulation(
          utils,
          days: ScraperUtils::DateRangeUtils.default_days,
          everytime: ScraperUtils::DateRangeUtils.default_everytime,
          max_period: 3,
          visualize: !ENV['VISUALIZE']&.empty?
        )

        # Output the stats table
        puts stats[:table]

        # Basic verification of the algorithm properties
        expect(utils.max_period_used).to eq(3)
        expect(stats[:max_unchecked_streak]).to be <= 3
        expect(stats[:coverage_percentage]).to eq(100)

        # Verify load distribution
        avg = 36.9
        expect(stats[:avg_checked_per_day]).to be_between(avg - 1, avg + 1)
        expect(stats[:min_checked_per_day]).to be_between(avg - 5, avg)
        expect(stats[:max_checked_per_day]).to be_between(avg, avg + 5)
      end

      it "provides good coverage with realistic parameters for 5 days", :aggregate_failures do
        # Runs
        stats = DateRangeSimulator.run_simulation(
          utils,
          days: ScraperUtils::DateRangeUtils.default_everytime + 2 * 2 + 3 * 3 + 5 * 5 + 3,
          everytime: ScraperUtils::DateRangeUtils.default_everytime,
          max_period: 5,
          visualize: !ENV['VISUALIZE']&.empty?
        )

        # Output the stats table
        puts stats[:table]

        # Basic verification of the algorithm properties
        expect(utils.max_period_used).to eq(5)
        expect(stats[:max_unchecked_streak]).to be <= 5
        expect(stats[:coverage_percentage]).to eq(100)

        # Verify load distribution
        avg = 30.7 # would prefer much lower than 36.9
        expect(stats[:avg_checked_per_day]).to be_between(avg - 1, avg + 1)
        expect(stats[:min_checked_per_day]).to be_between(avg - 10, avg)
        expect(stats[:max_checked_per_day]).to be_between(avg, avg + 10)
      end

      it "provides good coverage with realistic parameters for 8 days", :aggregate_failures do
        # Run a 60-day simulation to ensure all days get checked
        stats = DateRangeSimulator.run_simulation(
          utils,
          days: ScraperUtils::DateRangeUtils.default_everytime + 2 * 2 + 3 * 3 + 5 * 5 + 8 * 8 + 4,
          everytime: ScraperUtils::DateRangeUtils.default_everytime,
          max_period: 8,
          visualize: !ENV['VISUALIZE']&.empty?
        )

        # Output the stats table
        puts stats[:table]

        # Basic verification of the algorithm properties
        expect(utils.max_period_used).to eq(8)
        expect(stats[:max_unchecked_streak]).to be <= 8
        expect(stats[:coverage_percentage]).to eq(100)

        # Verify load distribution
        avg = 19.6 # decent enough though nit as good as I hoped
        expect(stats[:avg_checked_per_day]).to be_between(avg - 5, avg + 5)
        expect(stats[:min_checked_per_day]).to be_between(avg - 8, avg)
        expect(stats[:max_checked_per_day]).to be_between(avg, avg + 5)
      end
    end
  end
end
