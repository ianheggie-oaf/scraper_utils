# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe 'ScraperUtils::MiscUtils' do
  describe "#throttle_block" do
    context 'when run the first time' do
      it 'does not sleep' do
        expect(ScraperUtils::MiscUtils).not_to receive(:sleep)
        was_called = false
        ScraperUtils::MiscUtils.throttle_block do
          was_called = true
        end
        expect(was_called).to be_truthy
      end

      it 'sets pause interval for next time' do
        was_called = false
        ScraperUtils::MiscUtils.throttle_block do
          sleep(0.01)
          was_called = true
        end
        expect(was_called).to be_truthy

        expect(ScraperUtils::MiscUtils.pause_duration).to be_between(0.5, 0.55)
      end
    end

    context 'when run subsequently' do
      it 'pauses before calling the block' do
        ScraperUtils::MiscUtils.pause_duration = 4.5
        expect(ScraperUtils::MiscUtils).to receive(:sleep).with(4.5)
        was_called = false
        ScraperUtils::MiscUtils.throttle_block do
          was_called = true
        end
        expect(was_called).to be_truthy
      end
    end

  end
end
