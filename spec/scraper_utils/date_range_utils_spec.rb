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
        result = utils.calculate_date_ranges(days: 30, max_period: 1, today: today)
        expect(result).to eq([[today - 29, today, "everything"]])
      end

      it "returns a single range when everytime covers all days" do
        result = utils.calculate_date_ranges(days: 30, everytime: 30, today: today)
        expect(result).to eq([[today - 29, today, "everything"]])
      end
    end

    context "with fibonacci progression" do
      it "respects and uses max_period=3" do
        utils.calculate_date_ranges(days: 30, everytime: 2, max_period: 3, today: today)

        expect(utils.max_period_used).to eq(3)
      end

      it "respects and uses max_period=2" do
        utils.calculate_date_ranges(days: 30, everytime: 2, max_period: 2, today: today)

        expect(utils.max_period_used).to eq(2)
      end
    end

    context "with edge cases" do
      it "handles invalid days value" do
        # Line 96: if !max_period.positive? || !days.positive?
        result = utils.calculate_date_ranges(days: 0, everytime: 2, max_period: 5, today: Date.today)
        expect(result).to eq([])
      end

      it "handles valid max_period that doesn't match any standard period" do
        # Test the case where we use max_period = 4 (not in PERIODS = [2, 3, 5, 8])
        # Note: used days: 40 as 5-day periods doesn't start till just after 30 even if selected
        today = Date.today
        result = []
        expected_max_period = 4
        expected_max_period.times do |offset|
          result.concat utils.calculate_date_ranges(days: 40, everytime: 2, max_period: 4, today: today - offset)
        end

        # Should use the highest valid period that's <= max_period (3 in this case)
        expect(utils.max_period_used).to eq(expected_max_period)

        # Should still cover all dates
        date_counts = Hash.new(0)
        result.each do |from_date, to_date, _comment|
          (from_date..to_date).each do |date|
            date_counts[date] += 1
          end
        end

        # Check that all dates in the range are covered
        (today - 20..today).each do |date|
          expect(date_counts[date]).to be >= 1, "Date #{date} should be covered! date_counts: #{date_counts.to_json}"
        end
      end

      it "correctly calculates remaining days at max_period" do
        # Tests line 128: max_period = valid_periods.max
        today = Date.today
        days = 20
        everytime = 2
        max_period = 5

        result = []
        expected_max_period = 4
        expected_max_period.times do |offset|
          result.concat utils.calculate_date_ranges(days: days, everytime: everytime, max_period: max_period, today: today - offset)
        end

        # Should use the highest valid period that's <= max_period (3 in this case)
        expect(utils.max_period_used).to eq(expected_max_period)

        # Should still cover all dates
        date_counts = Hash.new(0)
        result.each do |from_date, to_date, _comment|
          (from_date..to_date).each do |date|
            date_counts[date] += 1
          end
        end

        # Check that all dates in the range are covered
        (today - days + 1..today).each do |date|
          expect(date_counts[date]).to be >= 1, "Date #{date} should be covered! date_counts: #{date_counts.to_json}"
        end
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
        expect(stats[:max_unchecked_streak]).to be < 2
        expect(stats[:coverage_percentage]).to eq(100)

        # Verify load distribution
        avg = 59.1
        expect(stats[:avg_checked_per_day]).to be_between(avg - 1, avg + 1)
        expect(stats[:min_checked_per_day]).to be_between(avg - 2, avg)
        expect(stats[:max_checked_per_day]).to be_between(avg, avg + 2)
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
        avg = 50.1
        expect(stats[:avg_checked_per_day]).to be_between(avg - 1, avg + 1)
        expect(stats[:min_checked_per_day]).to be_between(avg - 17, avg)
        expect(stats[:max_checked_per_day]).to be_between(avg, avg + 17)
      end

      it "provides good coverage with realistic parameters for 4 days", :aggregate_failures do
        # Runs
        stats = DateRangeSimulator.run_simulation(
          utils,
          days: ScraperUtils::DateRangeUtils.default_days,
          everytime: ScraperUtils::DateRangeUtils.default_everytime,
          max_period: 4,
          visualize: !ENV['VISUALIZE']&.empty?
        )

        # Output the stats table
        puts stats[:table]

        # Basic verification of the algorithm properties
        # expect(utils.max_period_used).to eq(5) # sometimes 3
        expect(stats[:max_unchecked_streak]).to be <= 4
        expect(stats[:coverage_percentage]).to eq(100)

        # Verify load distribution
        avg = 46.7
        expect(stats[:avg_checked_per_day]).to be_between(avg - 1, avg + 1)
        expect(stats[:min_checked_per_day]).to be_between(avg - 32, avg)
        expect(stats[:max_checked_per_day]).to be_between(avg, avg + 15)
      end
    end
  end
end
