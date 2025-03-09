# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::RandomizeUtils do
  describe '.randomize_order' do
    let(:input_collection) { [1, 2, 3, 4, 5] }

    context 'when not in random mode' do
      before { described_class.random = false }
      after { described_class.reset! }

      it 'returns the original collection' do
        expect(described_class.randomize_order(input_collection)).to eq(input_collection)
      end
    end

    context 'when in random mode' do
      before { described_class.random = true }

      it 'returns a randomized collection' do
        randomized = described_class.randomize_order(input_collection)
        expect(randomized).to match_array(input_collection)
        expect(randomized).not_to eq(input_collection)
      end

      it 'handles different collection types' do
        set_collection = Set.new(input_collection)
        randomized = described_class.randomize_order(set_collection)
        expect(randomized).to match_array(set_collection)
      end
    end
  end

  describe '.random?' do
    context 'when MORPH_NOT_RANDOM is set' do
      before do
        ENV['MORPH_NOT_RANDOM'] = '1'
        described_class.reset!
      end
      after { ENV.delete('MORPH_NOT_RANDOM') }

      it 'returns false' do
        expect(described_class.random?).to be(false)
      end
    end

    context 'when MORPH_NOT_RANDOM is not set' do
      before do
        ENV.delete('MORPH_NOT_RANDOM')
        described_class.reset!
      end

      it 'returns true' do
        expect(described_class.random?).to be(true)
      end
    end
  end

  describe '.random=' do
    after { described_class.reset! }
    it 'allows manually setting random mode' do
      described_class.random = false
      expect(described_class.random?).to be(false)

      described_class.random = true
      expect(described_class.random?).to be(true)
    end
  end
end
