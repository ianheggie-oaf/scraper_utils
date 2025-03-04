# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe ScraperUtils::MechanizeActions do
  let(:agent) { instance_double('Mechanize') }
  let(:page) { instance_double('Mechanize::Page') }
  let(:next_page) { instance_double('Mechanize::Page') }
  let(:link) { instance_double('Mechanize::Link', href: 'https://example.com/next', text: '  Find an application  ') }

  subject { described_class.new(agent) }

  describe '#initialize' do
    it 'initializes with an agent' do
      expect(subject.agent).to eq(agent)
      expect(subject.results).to eq([])
    end

    it 'accepts replacements' do
      replacements = { FROM_DATE: '2022-01-01' }
      action_processor = described_class.new(agent, replacements)
      expect(action_processor.agent).to eq(agent)
      expect(action_processor.results).to eq([])
    end
  end

  describe '#process' do
    context 'with click actions' do
      before do
        allow(page).to receive(:links).and_return([link])
        allow(link).to receive(:click).and_return(next_page)
      end

      it 'processes a click action and returns the resulting page' do
        actions = [[:click, 'Find an application']]

        result = subject.process(page, actions)

        expect(result).to eq(next_page)
        expect(subject.results.size).to eq(1)
        expect(subject.results[0][:action]).to eq(:click)
        expect(subject.results[0][:target]).to eq('Find an application')
      end

      it 'selects from an array of options for a click action' do
        actions = [[:click, ['Find an application', 'Another option']]]

        # Allow ScraperUtils::CycleUtils.pick to be called and return the first option
        allow(ScraperUtils::CycleUtils).to receive(:pick).and_return('Find an application')

        result = subject.process(page, actions)

        expect(result).to eq(next_page)
        expect(subject.results[0][:action]).to eq(:click)
        expect(subject.results[0][:target]).to eq('Find an application')
      end
    end

    context 'with block actions' do
      it 'executes a block action' do
        # Define a block that returns a page and a result
        custom_result = { custom: 'value' }
        block = lambda do |current_page, args, agent, results|
          expect(current_page).to eq(page)
          expect(args).to be_empty
          expect(agent).to eq(subject.agent)
          expect(results).to be_an(Array)
          [next_page, custom_result]
        end

        actions = [[:block, block]]

        result = subject.process(page, actions)

        expect(result).to eq(next_page)
        expect(subject.results[0]).to eq(custom_result)
      end
    end

    context 'with unknown action types' do
      it 'raises an error for unknown action types' do
        actions = [[:unknown_action, 'some value']]

        expect { subject.process(page, actions) }.to raise_error(ArgumentError, /Unknown action type/)
      end
    end

    context 'with chained actions' do
      let(:final_page) { instance_double('Mechanize::Page') }
      let(:link2) { instance_double('Mechanize::Link', href: 'https://example.com/final', text: 'Next step') }

      before do
        allow(page).to receive(:links).and_return([link])
        allow(link).to receive(:click).and_return(next_page)
        allow(next_page).to receive(:links).and_return([link2])
        allow(link2).to receive(:click).and_return(final_page)
      end

      it 'processes multiple actions in sequence' do
        actions = [
          [:click, 'Find an application'],
          [:click, 'Next step']
        ]

        result = subject.process(page, actions)

        expect(result).to eq(final_page)
        expect(subject.results.size).to eq(2)
        expect(subject.results[0][:action]).to eq(:click)
        expect(subject.results[0][:target]).to eq('Find an application')
        expect(subject.results[1][:action]).to eq(:click)
        expect(subject.results[1][:target]).to eq('Next step')
      end
    end
  end

  describe 'element selection' do
    context 'with text selectors' do
      let(:fragment_link) { instance_double('Mechanize::Link', href: '#fragment', text: 'Find an application') }
      let(:normal_link) { instance_double('Mechanize::Link', href: 'https://example.com/next', text: 'Find an application') }
      let(:long_link) { instance_double('Mechanize::Link',
                                        href: 'https://example.com/long/path',
                                        text: 'Find an application with extra text') }

      before do
        allow(page).to receive(:links).and_return([fragment_link, normal_link, long_link])
        allow(normal_link).to receive(:click).and_return(next_page)
      end

      it 'filters out fragment links and prefers shorter text matches' do
        actions = [[:click, 'Find an application']]

        result = subject.process(page, actions)

        expect(result).to eq(next_page)
        expect(subject.results[0][:action]).to eq(:click)
        expect(subject.results[0][:target]).to eq('Find an application')
      end

      it 'raises an error when no matching links are found' do
        actions = [[:click, 'Non-existent link']]

        expect { subject.process(page, actions) }.to raise_error(/Unable to find click target/)
      end

      it 'performs case-insensitive matching when no exact match found' do
        lowercase_link = instance_double('Mechanize::Link',
                                         href: 'https://example.com/lower',
                                         text: 'find an application')
        allow(page).to receive(:links).and_return([lowercase_link])
        allow(lowercase_link).to receive(:click).and_return(next_page)

        actions = [[:click, 'Find an Application']]

        result = subject.process(page, actions)

        expect(result).to eq(next_page)
        expect(subject.results[0][:action]).to eq(:click)
        expect(subject.results[0][:target]).to eq('Find an Application')
      end
    end

    context 'with css selectors' do
      before do
        allow(page).to receive(:at_css).with('.button').and_return(link)
        allow(link).to receive(:click).and_return(next_page)
      end

      it 'finds elements using css selectors' do
        actions = [[:click, 'css:.button']]

        result = subject.process(page, actions)

        expect(result).to eq(next_page)
        expect(subject.results[0][:action]).to eq(:click)
        expect(subject.results[0][:target]).to eq('css:.button')
      end

      it 'raises an error when no elements match the CSS selector' do
        allow(page).to receive(:at_css).with('.non-existent').and_return(nil)

        actions = [[:click, 'css:.non-existent']]

        expect { subject.process(page, actions) }.to raise_error(/Unable to find click target/)
      end
    end

    context 'with xpath selectors' do
      before do
        allow(page).to receive(:at_xpath).with('//a[@class="button"]').and_return(link)
        allow(link).to receive(:click).and_return(next_page)
      end

      it 'finds elements using xpath selectors' do
        actions = [[:click, 'xpath://a[@class="button"]']]

        result = subject.process(page, actions)

        expect(result).to eq(next_page)
        expect(subject.results[0][:action]).to eq(:click)
        expect(subject.results[0][:target]).to eq('xpath://a[@class="button"]')
      end

      it 'raises an error when no elements match the XPath selector' do
        allow(page).to receive(:at_xpath).with('//non-existent').and_return(nil)

        actions = [[:click, 'xpath://non-existent']]

        expect { subject.process(page, actions) }.to raise_error(/Unable to find click target/)
      end
    end
  end

  describe 'replacements' do
    before do
      allow(page).to receive(:links).and_return([link])
      allow(link).to receive(:click).and_return(next_page)
    end

    it 'applies replacements to action parameters' do
      replacements = { DATE: '2022-01-01' }
      subject = described_class.new(agent, replacements)

      # Mock a link with text that will match after replacement
      link_with_template = instance_double('Mechanize::Link',
                                           href: 'https://example.com/search',
                                           text: 'Search 2022-01-01')
      allow(page).to receive(:links).and_return([link_with_template])
      allow(link_with_template).to receive(:click).and_return(next_page)

      actions = [[:click, 'Search {DATE}']]

      result = subject.process(page, actions)

      expect(result).to eq(next_page)
      expect(subject.results[0][:action]).to eq(:click)
      expect(subject.results[0][:target]).to eq("Search #{replacements[:DATE]}")
    end

    it 'applies replacements to array options before selecting one' do
      replacements = { DATE: '2022-01-01' }
      subject = described_class.new(agent, replacements)

      # Mock CycleUtils to return the replaced option
      allow(ScraperUtils::CycleUtils).to receive(:pick).and_return("Search #{replacements[:DATE]}")

      # Mock a link that matches the replaced text
      link_with_date = instance_double('Mechanize::Link',
                                       href: 'https://example.com/search',
                                       text: "Search #{replacements[:DATE]}")
      allow(page).to receive(:links).and_return([link_with_date])
      allow(link_with_date).to receive(:click).and_return(next_page)

      actions = [[:click, ['Search {DATE}', 'Another option']]]

      result = subject.process(page, actions)

      expect(result).to eq(next_page)
      expect(subject.results[0][:action]).to eq(:click)
      expect(subject.results[0][:target]).to eq("Search #{replacements[:DATE]}")
    end
  end
end
