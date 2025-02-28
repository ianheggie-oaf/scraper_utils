# frozen_string_literal: true

require 'spec_helper'
require 'scraper_utils/randomize_utils'

RSpec.describe ScraperUtils::RandomizeUtils do
  describe '.randomize_order' do
    let(:input_collection) { [1, 2, 3, 4, 5] }

    context 'when in sequential mode' do
      before { described_class.sequential = true }
      after { described_class.sequential = false }

      it 'returns the original collection' do
        expect(described_class.randomize_order(input_collection)).to eq(input_collection)
      end
    end

    context 'when not in sequential mode' do
      before { described_class.sequential = false }

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

  describe '.sequential?' do
    context 'when MORPH_PROCESS_SEQUENTIALLY is set' do
      before { ENV['MORPH_PROCESS_SEQUENTIALLY'] = 'true' }
      after { ENV.delete('MORPH_PROCESS_SEQUENTIALLY') }

      it 'returns true' do
        expect(described_class.sequential?).to be(true)
      end
    end

    context 'when MORPH_PROCESS_SEQUENTIALLY is not set' do
      before { ENV.delete('MORPH_PROCESS_SEQUENTIALLY') }

      it 'returns false' do
        expect(described_class.sequential?).to be(false)
      end
    end
  end

  describe '.sequential=' do
    it 'allows manually setting sequential mode' do
      described_class.sequential = true
      expect(described_class.sequential?).to be(true)

      described_class.sequential = false
      expect(described_class.sequential?).to be(false)
    end
  end
end
