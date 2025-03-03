# frozen_string_literal: true

require 'date'

require_relative '../spec_helper'
require_relative '../../lib/scraper_utils/cycle_utils'

RSpec.describe ScraperUtils::CycleUtils do
  before do
    # Clear any environment variables before each test
    ENV.delete('CYCLE_POSITION')
  end

  describe '.position' do
    context 'with default date' do
      it 'returns correct position based on Julian day' do
        # January 1, 2024, has JD 2460311
        allow(Date).to receive(:today).and_return(Date.new(2024, 1, 1))

        # With cycle of 2: 2460311 % 2 = 1
        position = described_class.position(2)
        expect(position).to eq(1)
        expect(position.odd?).to be true
        expect(position.even?).to be false

        # With cycle of 7: 2460311 % 7 = 0
        expect(described_class.position(7)).to eq(0)
      end

      it 'properly handles even Julian days' do
        # January 2, 2024, has JD 2460312
        allow(Date).to receive(:today).and_return(Date.new(2024, 1, 2))

        # With cycle of 2: 2460312 % 2 = 0
        position = described_class.position(2)
        expect(position).to eq(0)
        expect(position.even?).to be true
        expect(position.odd?).to be false

        # With cycle of 7: 2460312 % 7 = 1
        expect(described_class.position(7)).to eq(1)
      end
    end

    context 'with custom date' do
      it 'uses the provided date for Julian day calculation' do
        # January 5, 2024, has JD 2460315
        date = Date.new(2024, 1, 5)

        # With cycle of 2: 2460315 % 2 = 1
        expect(described_class.position(2, date: date)).to eq(1)

        # With cycle of 3: 2460315 % 3 = 0
        expect(described_class.position(3, date: date)).to eq(0)
      end
    end

    context 'with environment variable override' do
      it 'uses CYCLE_POSITION environment variable when set' do
        ENV['CYCLE_POSITION'] = '2'

        # With cycle of 2: 2 % 2 = 0
        position = described_class.position(2)
        expect(position).to eq(0)
        expect(position.even?).to be true

        # With cycle of 3: 2 % 3 = 2
        expect(described_class.position(3)).to eq(2)
      end
    end
  end

  describe '.pick' do
    context 'with default date' do
      it 'selects the correct array element based on Julian day' do
        # January 1, 2024, has JD 2460311
        allow(Date).to receive(:today).and_return(Date.new(2024, 1, 1))

        # With array [7, 28]: 2460311 % 2 = 1, selects element at index 1
        expect(described_class.pick([7, 28])).to eq(28)

        # With array ['short', 'medium', 'long']: 2460311 % 3 = 2, selects element at index 2
        expect(described_class.pick(%w[short medium long])).to eq('long')
      end

      it 'cycles through array elements on consecutive days' do
        # January 2, 3, 4, 2024 have JD 2460312, 2460313, 2460314
        days = [
          Date.new(2024, 1, 2),  # JD 2460312 % 3 = 0
          Date.new(2024, 1, 3),  # JD 2460313 % 3 = 1
          Date.new(2024, 1, 4)   # JD 2460314 % 3 = 2
        ]

        cycle = %w[north central south]

        # Each day should get the next region in the cycle
        days.each_with_index do |day, i|
          allow(Date).to receive(:today).and_return(day)
          expect(described_class.pick(cycle)).to eq(cycle[i])
        end
      end
    end

    context 'with custom date' do
      it 'uses the provided date for array element selection' do
        # January 5, 2024, has JD 2460315
        date = Date.new(2024, 1, 5)

        # With array [7, 28]: 2460315 % 2 = 1, selects element at index 1
        expect(described_class.pick([7, 28], date: date)).to eq(28)

        # With array ['short', 'medium', 'long']: 2460315 % 3 = 0, selects element at index 0
        expect(described_class.pick(%w[short medium long], date: date)).to eq('short')
      end
    end

    context 'with environment variable override' do
      it 'uses CYCLE_POSITION environment variable for array element selection' do
        ENV['CYCLE_POSITION'] = '2'

        # With array [7, 28]: 2 % 2 = 0, selects element at index 0
        expect(described_class.pick([7, 28])).to eq(7)

        # With array ['short', 'medium', 'long']: 2 % 3 = 2, selects element at index 2
        expect(described_class.pick(%w[short medium long])).to eq('long')
      end
    end
  end

  describe 'alternate behavior example from README' do
    it 'correctly implements the toggle example' do
      # Test the "alternate = ScraperUtils::CycleUtils.position(2).even?" example

      # January 1, 2024, has JD 2460311 (odd)
      allow(Date).to receive(:today).and_return(Date.new(2024, 1, 1))
      alternate = described_class.position(2).even?
      expect(alternate).to be false

      # January 2, 2024, has JD 2460312 (even)
      allow(Date).to receive(:today).and_return(Date.new(2024, 1, 2))
      alternate = described_class.position(2).even?
      expect(alternate).to be true
    end
  end
end
