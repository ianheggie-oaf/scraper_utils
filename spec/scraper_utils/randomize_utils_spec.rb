# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::RandomizeUtils do
  describe '.randomize_order' do
    let(:input_collection) { [1, 2, 3, 4, 5] }

    context 'when in sequential mode' do
      before { described_class.sequential = true }
      after { described_class.instance_variable_set(:@sequential, nil) }

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
      before do
        described_class.sequential = nil
        ENV['MORPH_PROCESS_SEQUENTIALLY'] = 'true'
      end
      after { ENV.delete('MORPH_PROCESS_SEQUENTIALLY') }

      it 'returns true' do
        described_class.sequential = nil
        expect(described_class.sequential?).to be(true)
      end
    end

    context 'when MORPH_PROCESS_SEQUENTIALLY is not set' do
      before do
        described_class.sequential = nil
        ENV.delete('MORPH_PROCESS_SEQUENTIALLY')
      end

      it 'returns false' do
        described_class.sequential = nil
        expect(described_class.sequential?).to be(false)
      end
    end
  end

  describe '.sequential=' do
    after { described_class.sequential = nil }
    it 'allows manually setting sequential mode' do
      described_class.sequential = true
      expect(described_class.sequential?).to be(true)

      described_class.sequential = false
      expect(described_class.sequential?).to be(false)
    end
  end
end
