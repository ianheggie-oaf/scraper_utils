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
      it "creates ranges with fibonacci sequence periods" do
        # With max_period = 3, we should see periods 1, 2, 3
        result = utils.calculate_date_ranges(days: 20, everytime: 2, max_period: 3, today: today).reverse

        # Should include everytime days
        expect(result.first[0]).to be >= today - 2
        expect(result.first[1]).to eq(today)

        # Verify the periods through the ranges
        expected_periods = [2, 3]
        periods_found = []

        # Extract the periods from the result
        result.each do |range|
          # Range size is end - start + 1
          range_size = (range[1] - range[0]).to_i + 1
          periods_found << range_size
        end

        # We might not have all periods depending on the parameters
        expected_periods.each do |period|
          expect(periods_found).to include(period)
        end
      end

      it "respects max_period" do
        utils.calculate_date_ranges(days: 30, everytime: 2, max_period: 5, today: today)

        expect(utils.max_period_used).to eq(5)
      end
    end

    context "simulation testing" do
      it "provides good coverage with realistic parameters", :aggregate_failures do
        # Run a 60-day simulation to ensure all days get checked
        stats = DateRangeSimulator.run_simulation(
          utils,
          days: 30,
          everytime: 2,
          max_period: 5
        )

        # Output the stats table
        puts stats[:table]

        # Basic verification of the algorithm properties
        expect(stats[:max_unchecked_streak]).to be <= 5
        expect(stats[:coverage_percentage]).to eq(100)

        # Verify load distribution
        expect(stats[:avg_checked_per_day]).to be_between(5, 15)
        expect(stats[:max_checked_per_day]).to be <= 30
      end
    end

  end
end
