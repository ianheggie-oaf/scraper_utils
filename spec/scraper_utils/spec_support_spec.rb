# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe ScraperUtils::SpecSupport do
  describe '.authority_label' do
    context 'with valid results' do
      let(:results) { [{ 'authority_label' => 'sydney' }, { 'authority_label' => 'sydney' }] }

      it 'returns the authority label' do
        expect(described_class.authority_label(results)).to eq('sydney')
      end

      it 'adds prefix and suffix when provided' do
        expect(described_class.authority_label(results, prefix: 'test_', suffix: '_data')).to eq('test_sydney_data')
      end
    end

    context 'with nil results' do
      it 'returns nil' do
        expect(described_class.authority_label(nil)).to be_nil
      end
    end

    context 'with empty results' do
      it 'returns nil' do
        expect(described_class.authority_label([])).to be_nil
      end
    end

    context 'with multiple authority labels' do
      let(:results) { [{ 'authority_label' => 'sydney' }, { 'authority_label' => 'melbourne' }] }

      it 'raises an error' do
        expect { described_class.authority_label(results) }.to raise_error(RuntimeError, 'Expected one authority_label, not ["sydney", "melbourne"]')
      end
    end

    context 'with no authority_label keys' do
      let(:results) { [{ 'other_key' => 'value' }] }

      it 'returns nil' do
        expect(described_class.authority_label(results)).to be_nil
      end
    end
  end

  describe '.geocodable?' do
    context 'with valid addresses' do
      it 'returns true for complete address' do
        expect(described_class.geocodable?('123 Smith Street, Sydney NSW 2000')).to be true
      end

      it 'returns true for address with unit' do
        expect(described_class.geocodable?('Unit 5, 123 Smith Street, Sydney NSW 2000')).to be true
      end

      it 'returns true for address with lot' do
        expect(described_class.geocodable?('Lot 10, 123 Smith Street, Sydney NSW 2000')).to be true
      end

      it 'returns true for abbreviated street types' do
        expect(described_class.geocodable?('123 Smith St, Sydney NSW 2000')).to be true
        expect(described_class.geocodable?('123 Smith Ave, Sydney NSW 2000')).to be true
        expect(described_class.geocodable?('123 Smith Rd, Sydney NSW 2000')).to be true
      end

      it "returns true for camel case street and uppercased suburb and state with commas with DEBUG set" do
        prev_debug = ENV['DEBUG']
        ENV['DEBUG'] = '1'
        expect(described_class.geocodable?('70 Pacific Highway, TUGGERAH, NSW')).to be true
      ensure
        ENV['DEBUG'] = prev_debug
      end
    end

    context 'with invalid addresses' do
      it 'returns false for nil' do
        expect(described_class.geocodable?(nil)).to be false
      end

      it 'returns false for empty string' do
        expect(described_class.geocodable?('')).to be false
      end

      it 'outputs debug output when DEBUG variable is set' do
        prev_debug = ENV['DEBUG']
        ENV['DEBUG'] = '1'
        expect { described_class.geocodable?('lot 12 folio a123') }
          .to output(/address: lot 12 folio a123 is not geocodable, missing street type, postcode\/Uppercase suburb, state/).to_stdout
      ensure
        ENV['DEBUG'] = prev_debug
      end

      it 'returns false for address missing state' do
        expect(described_class.geocodable?('123 Smith Street, Sydney 2000')).to be false
      end

      it 'returns false for address missing postcode' do
        expect(described_class.geocodable?('123 Smith Street, Sydney NSW')).to be false
      end

      it 'returns false for address missing street type' do
        expect(described_class.geocodable?('123 Smith, Sydney NSW 2000')).to be false
      end
    end
  end

  describe '.placeholder?' do
    context 'with placeholder text' do
      it 'returns true for various placeholder patterns' do
        expect(described_class.placeholder?('no description')).to be true
        expect(described_class.placeholder?('NOT AVAILABLE')).to be true
        expect(described_class.placeholder?('to be confirmed')).to be true
        expect(described_class.placeholder?('tbc')).to be true
        expect(described_class.placeholder?('n/a')).to be true
      end
    end

    context 'with valid text' do
      it 'returns false for legitimate descriptions' do
        expect(described_class.placeholder?('Construction of new building')).to be false
        expect(described_class.placeholder?('Renovation works')).to be false
      end

      it 'returns false for nil' do
        expect(described_class.placeholder?(nil)).to be false
      end
    end
  end

  describe '.reasonable_description?' do
    context 'with reasonable descriptions' do
      it 'returns true for descriptions with 3+ words' do
        expect(described_class.reasonable_description?('Construction of building')).to be true
        expect(described_class.reasonable_description?('Major renovation project works')).to be true
      end
    end

    context 'with unreasonable descriptions' do
      it 'returns false for placeholder text' do
        expect(described_class.reasonable_description?('no description')).to be false
        expect(described_class.reasonable_description?('n/a')).to be false
      end

      it 'returns false for short descriptions' do
        expect(described_class.reasonable_description?('short')).to be false
        expect(described_class.reasonable_description?('two words')).to be false
      end

      it 'returns false for nil' do
        expect(described_class.reasonable_description?(nil)).to be false
      end
    end
  end

  describe '.validate_addresses_are_geocodable!' do
    let(:geocodable_results) do
      [
        { 'address' => '123 Smith Street, Sydney NSW 2000' },
        { 'address' => '456 Jones Avenue, Melbourne VIC 3000' },
        { 'address' => '789 Brown Road, Brisbane QLD 4000' }
      ]
    end

    let(:non_geocodable_results) do
      [
        { 'address' => 'Invalid address' },
        { 'address' => 'Another bad address' }
      ]
    end

    context 'with sufficient geocodable addresses' do
      it 'returns count of geocodable addresses' do
        expect(described_class.validate_addresses_are_geocodable!(geocodable_results)).to eq(3)
      end

      it 'handles custom percentage and variation' do
        expect(described_class.validate_addresses_are_geocodable!(geocodable_results, percentage: 80, variation: 1)).to eq(3)
      end
    end

    context 'with insufficient geocodable addresses' do
      it 'raises error with default parameters' do
        expect { described_class.validate_addresses_are_geocodable!(non_geocodable_results) }.to raise_error(RuntimeError, /Expected at least .* geocodable addresses/)
      end

      it 'raises error with custom parameters' do
        expect { described_class.validate_addresses_are_geocodable!(non_geocodable_results, percentage: 80, variation: 1) }.to raise_error(RuntimeError, /Expected at least .* \(80% - 1\) geocodable addresses/)
      end
    end

    context 'with empty results' do
      it 'returns nil' do
        expect(described_class.validate_addresses_are_geocodable!([])).to be_nil
      end
    end
  end

  describe '.validate_descriptions_are_reasonable!' do
    let(:reasonable_results) do
      [
        { 'description' => 'Construction of new building' },
        { 'description' => 'Major renovation project works' },
        { 'description' => 'Simple building extension work' }
      ]
    end

    let(:unreasonable_results) do
      [
        { 'description' => 'no description' },
        { 'description' => 'n/a' }
      ]
    end

    context 'with sufficient reasonable descriptions' do
      it 'returns count of reasonable descriptions' do
        expect(described_class.validate_descriptions_are_reasonable!(reasonable_results)).to eq(3)
      end

      it 'handles custom percentage and variation' do
        expect(described_class.validate_descriptions_are_reasonable!(reasonable_results, percentage: 80, variation: 1)).to eq(3)
      end
    end

    context 'with insufficient reasonable descriptions' do
      it 'raises error with default parameters' do
        expect { described_class.validate_descriptions_are_reasonable!(unreasonable_results) }.to raise_error(RuntimeError, /Expected at least .* reasonable descriptions/)
      end

      it 'raises error with custom parameters' do
        expect { described_class.validate_descriptions_are_reasonable!(unreasonable_results, percentage: 80, variation: 1) }.to raise_error(RuntimeError, /Expected at least .* \(80% - 1\) reasonable descriptions/)
      end
    end

    context 'with empty results' do
      it 'returns nil' do
        expect(described_class.validate_descriptions_are_reasonable!([])).to be_nil
      end
    end
  end

  describe '.validate_uses_one_valid_info_url!' do
    let(:expected_url) { 'https://example.com/search' }
    let(:valid_results) do
      [
        { 'info_url' => expected_url, 'authority_label' => 'sydney' },
        { 'info_url' => expected_url, 'authority_label' => 'sydney' }
      ]
    end

    before do
      stub_request(:get, expected_url)
        .to_return(status: 200, body: 'Valid response', headers: { 'Content-Type' => 'text/html' })
    end

    context 'with valid single info_url' do
      it 'validates successfully' do
        expect { described_class.validate_uses_one_valid_info_url!(valid_results, expected_url) }.not_to raise_error
      end
    end

    context 'with multiple info_urls' do
      let(:multiple_url_results) do
        [
          { 'info_url' => 'https://example.com/url1', 'authority_label' => 'sydney' },
          { 'info_url' => 'https://example.com/url2', 'authority_label' => 'sydney' }
        ]
      end

      it 'raises error' do
        expect { described_class.validate_uses_one_valid_info_url!(multiple_url_results, expected_url) }.to raise_error(RuntimeError, /Expected all records to use one info_url/)
      end
    end

    context 'with wrong info_url' do
      let(:wrong_url_results) do
        [
          { 'info_url' => 'https://wrong.com/search', 'authority_label' => 'sydney' },
          { 'info_url' => 'https://wrong.com/search', 'authority_label' => 'sydney' }
        ]
      end

      it 'raises error' do
        expect { described_class.validate_uses_one_valid_info_url!(wrong_url_results, expected_url) }.to raise_error(RuntimeError, /Expected all records to use global info_url/)
      end
    end

    context 'when URL returns non-200 response' do
      before do
        stub_request(:get, expected_url)
          .to_return(status: 404, body: 'Not Found', headers: { 'Content-Type' => 'text/html' })
      end

      it 'raises Mechanize::ResponseCodeError error' do
        expect { described_class.validate_uses_one_valid_info_url!(valid_results, expected_url) }.to raise_error(Mechanize::ResponseCodeError)
      end
    end
  end

  describe '.validate_info_urls_have_expected_details!' do
    let(:results) do
      [
        { 'info_url' => 'https://example.com/1', 'council_reference' => 'REF001', 'address' => '123 Smith St', 'description' => 'Building work', 'authority_label' => 'sydney' },
        { 'info_url' => 'https://example.com/2', 'council_reference' => 'REF002', 'address' => '456 Jones Ave', 'description' => 'Renovation work', 'authority_label' => 'sydney' }
      ]
    end

    before do
      # Mock the pages to contain the expected content
      stub_request(:get, 'https://example.com/1')
        .to_return(status: 200, body: 'REF001 123 Smith St Building work', headers: { 'Content-Type' => 'text/html' })

      stub_request(:get, 'https://example.com/2')
        .to_return(status: 200, body: 'REF002 456 Jones Ave Renovation work', headers: { 'Content-Type' => 'text/html' })
    end

    context 'with sufficient passing detail checks' do
      it 'validates successfully' do
        expect { described_class.validate_info_urls_have_expected_details!(results) }.not_to raise_error
      end
    end

    context 'when URL returns non-200 response' do
      before do
        stub_request(:get, 'https://example.com/1')
          .to_return(status: 404, body: 'Not Found', headers: { 'Content-Type' => 'text/html' })
      end

      it 'raises Mechanize::ResponseCodeError error' do
        expect { described_class.validate_info_urls_have_expected_details!(results) }.to raise_error(Mechanize::ResponseCodeError)
      end
    end

    context 'when too many detail checks fail' do
      before do
        stub_request(:get, 'https://example.com/1')
          .to_return(status: 200, body: 'No matching content', headers: { 'Content-Type' => 'text/html' })
        stub_request(:get, 'https://example.com/2')
          .to_return(status: 200, body: 'No matching content', headers: { 'Content-Type' => 'text/html' })
      end

      it 'raises error when failure threshold exceeded' do
        expect { described_class.validate_info_urls_have_expected_details!(results, percentage: 90, variation: 0) }.to raise_error(RuntimeError, /Too many failures/)
      end
    end

    context 'with larger result set to test fibonacci sampling' do
      let(:large_results) do
        (1..10).map do |i|
          {
            'info_url' => "https://example.com/#{i}",
            'council_reference' => "REF#{i.to_s.rjust(3, '0')}",
            'address' => "#{i}23 Smith St",
            'description' => "Building work #{i}",
            'authority_label' => 'sydney'
          }
        end
      end

      before do
        ScraperUtils::MathsUtils.fibonacci_series(9).uniq.each do |i|
          stub_request(:get, "https://example.com/#{i + 1}")
            .to_return(status: 200, body: "REF#{(i + 1).to_s.rjust(3, '0')} #{i + 1}23 Smith St Building work #{i + 1}", headers: { 'Content-Type' => 'text/html' })
        end
      end

      it 'uses fibonacci sampling correctly' do
        expect { described_class.validate_info_urls_have_expected_details!(large_results) }.not_to raise_error
      end
    end
  end

  describe '.bot_protection_detected?' do
    let(:page_200) { double(code: '200', body: 'Normal page content') }
    let(:page_403) { double(code: '403', body: 'Forbidden') }
    let(:page_429) { double(code: '429', body: 'Too many requests') }
    let(:page_recaptcha) { double(code: '200', body: 'Please complete the reCAPTCHA challenge') }
    let(:page_cloudflare) { double(code: '200', body: 'Cloudflare security check in progress') }
    let(:page_human_check) { double(code: '200', body: 'Are you human? Please verify') }
    let(:page_no_body) { double(code: '200', body: nil) }

    context 'with bot protection HTTP codes' do
      it 'returns true for 403 status' do
        expect(described_class.bot_protection_detected?(page_403)).to be true
      end

      it 'returns true for 429 status' do
        expect(described_class.bot_protection_detected?(page_429)).to be true
      end
    end

    context 'with bot protection content' do
      it 'returns true for recaptcha' do
        expect(described_class.bot_protection_detected?(page_recaptcha)).to be true
      end

      it 'returns true for cloudflare' do
        expect(described_class.bot_protection_detected?(page_cloudflare)).to be true
      end

      it 'returns true for human verification' do
        expect(described_class.bot_protection_detected?(page_human_check)).to be true
      end
    end

    context 'without bot protection' do
      it 'returns false for normal page' do
        expect(described_class.bot_protection_detected?(page_200)).to be false
      end

      it 'returns false for page with no body' do
        expect(described_class.bot_protection_detected?(page_no_body)).to be false
      end
    end
  end

  describe '.validate_page_response' do
    let(:page_200) { double(code: '200', body: 'Normal content') }
    let(:page_403) { double(code: '403', body: 'Forbidden') }
    let(:page_bot_content) { double(code: '200', body: 'reCAPTCHA challenge') }

    context 'with bot_check_expected false' do
      it 'accepts 200 response' do
        expect { described_class.validate_page_response(page_200, false) }.not_to raise_error
      end

      it 'raises error for 403 response' do
        expect { described_class.validate_page_response(page_403, false) }.to raise_error(RuntimeError, /Expected 200 response/)
      end

      it 'raises error for bot protection content' do
        expect { described_class.validate_page_response(page_bot_content, false) }.not_to raise_error
      end
    end

    context 'with bot_check_expected true' do
      it 'accepts 200 response' do
        expect { described_class.validate_page_response(page_200, true) }.not_to raise_error
      end

      it 'accepts 403 response as bot protection' do
        expect { described_class.validate_page_response(page_403, true) }.not_to raise_error
      end

      it 'accepts bot protection content' do
        expect { described_class.validate_page_response(page_bot_content, true) }.not_to raise_error
      end
    end
  end
end
