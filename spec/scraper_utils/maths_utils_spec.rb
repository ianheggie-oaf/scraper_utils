# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::MathsUtils do
  describe '.fibonacci_series' do
    context 'with edge cases' do
      it 'returns just [0] for max 0' do
        expect(described_class.fibonacci_series(0)).to eq([0])
      end

      it 'returns [0, 1, 1] for max 1' do
        expect(described_class.fibonacci_series(1)).to eq([0, 1, 1])
      end

      it 'returns empty array for negative max' do
        expect(described_class.fibonacci_series(-1)).to eq([])
      end
    end

    context 'with small sequences' do
      it 'generates correct sequence up to 21' do
        expected = [0, 1, 1, 2, 3, 5, 8, 13, 21]
        expect(described_class.fibonacci_series(21)).to eq(expected)
      end

      it 'generates correct sequence up to 8' do
        expected = [0, 1, 1, 2, 3, 5, 8]
        expect(described_class.fibonacci_series(8)).to eq(expected)
      end

      it 'generates correct sequence up to 5' do
        expected = [0, 1, 1, 2, 3, 5]
        expect(described_class.fibonacci_series(5)).to eq(expected)
      end
    end

    context 'with larger sequences' do
      it 'generates correct sequence up to 900' do
        expected = [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610]
        expect(described_class.fibonacci_series(900)).to eq(expected)
      end

      it 'stops at correct boundary' do
        result = described_class.fibonacci_series(100)
        expect(result.last).to eq(89)
        expect(result).not_to include(144) # 144 > 100
      end
    end

    context 'with block given' do
      it 'yields each fibonacci number' do
        yielded_values = []
        described_class.fibonacci_series(5) { |fib| yielded_values << fib }
        expect(yielded_values).to eq([0, 1, 1, 2, 3, 5])
      end

      it 'returns the array even when block given' do
        result = described_class.fibonacci_series(5) { |fib| fib * 2 }
        expect(result).to eq([0, 1, 1, 2, 3, 5])
      end
    end

    context 'sequence properties' do
      it 'each number is sum of previous two (after initial 0, 1)' do
        result = described_class.fibonacci_series(100)
        (2...result.length).each do |i|
          expect(result[i]).to eq(result[i-1] + result[i-2])
        end
      end

      it 'starts with 0, 1 for any max >= 1' do
        expect(described_class.fibonacci_series(1)[0..1]).to eq([0, 1])
        expect(described_class.fibonacci_series(50)[0..1]).to eq([0, 1])
        expect(described_class.fibonacci_series(1000)[0..1]).to eq([0, 1])
      end

      it 'is monotonically increasing after first duplicate' do
        result = described_class.fibonacci_series(900)
        # Skip duplicate in initial 0,1,1
        (3...result.length).each do |i|
          expect(result[i]).to be > result[i-1]
        end
      end
    end
  end
end
