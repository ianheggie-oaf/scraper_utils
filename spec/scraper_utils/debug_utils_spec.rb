# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe ScraperUtils::DebugUtils do
  describe '.debug_request' do
    let(:method) { 'GET' }
    let(:url) { 'https://example.com' }

    context 'when debug mode is on' do
      before { allow(ScraperUtils).to receive(:debug?).and_return(true) }

      it 'prints request details' do
        expect {
          described_class.debug_request(method, url, parameters: { key: 'value' })
        }.to output(/GET https:\/\/example.com/).to_stdout
      end

      it 'prints parameters' do
        expect {
          described_class.debug_request(method, url, parameters: { key: 'value' })
        }.to output(/Parameters:/).to_stdout
      end

      it 'prints headers' do
        expect {
          described_class.debug_request(method, url, headers: { 'Content-Type': 'application/json' })
        }.to output(/Headers:/).to_stdout
      end

      it 'prints body' do
        expect {
          described_class.debug_request(method, url, body: { data: 'test' })
        }.to output(/Body:/).to_stdout
      end
    end

    context 'when debug mode is off' do
      before { allow(ScraperUtils).to receive(:debug?).and_return(false) }

      it 'does not print anything' do
        expect {
          described_class.debug_request(method, url)
        }.not_to output.to_stdout
      end
    end
  end

  describe '.debug_page' do
    let(:page) { double('Mechanize::Page') }
    let(:message) { 'Test debug page' }

    context 'when debug mode is on' do
      before { allow(ScraperUtils).to receive(:debug?).and_return(true) }

      it 'prints page details' do
        allow(page).to receive(:uri).and_return('https://example.com')
        allow(page).to receive(:at).with('title').and_return(double(text: 'Test Page'))
        allow(page).to receive(:body).and_return('<html>Test Content</html>')

        expect {
          described_class.debug_page(page, message)
        }.to output(/DEBUG: Test debug page/).to_stdout
      end

      it 'handles missing title' do
        allow(page).to receive(:uri).and_return('https://example.com')
        allow(page).to receive(:at).with('title').and_return(nil)
        allow(page).to receive(:body).and_return('<html>Test Content</html>')

        expect {
          described_class.debug_page(page, message)
        }.to output(/DEBUG: Test debug page/).to_stdout
      end
    end

    context 'when debug mode is off' do
      before { allow(ScraperUtils).to receive(:debug?).and_return(false) }

      it 'does not print anything' do
        expect {
          described_class.debug_page(page, message)
        }.not_to output.to_stdout
      end
    end
  end

  describe '.debug_selector' do
    let(:page) { double('Mechanize::Page') }
    let(:selector) { 'div.test' }
    let(:message) { 'Test selector' }

    context 'when debug mode is on' do
      before { allow(ScraperUtils).to receive(:debug?).and_return(true) }

      it 'prints selector details when element found' do
        element = double(to_html: '<div class="test">Test Content</div>')
        allow(page).to receive(:at).with(selector).and_return(element)

        expect {
          described_class.debug_selector(page, selector, message)
        }.to output(/DEBUG: Test selector/).to_stdout
      end

      it 'prints page body when element not found' do
        allow(page).to receive(:at).with(selector).and_return(nil)
        allow(page).to receive(:body).and_return('<html>Test Content</html>')

        expect {
          described_class.debug_selector(page, selector, message)
        }.to output(/Element not found/).to_stdout
      end
    end

    context 'when debug mode is off' do
      before { allow(ScraperUtils).to receive(:debug?).and_return(false) }

      it 'does not print anything' do
        expect {
          described_class.debug_selector(page, selector, message)
        }.not_to output.to_stdout
      end
    end
  end
end
