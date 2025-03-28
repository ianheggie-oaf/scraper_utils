# frozen_string_literal: true

module ScraperUtils
  # Class for executing a series of mechanize actions with flexible replacements
  #
  # @example Basic usage
  #   agent = ScraperUtils::MechanizeUtils.mechanize_agent
  #   page = agent.get("https://example.com")
  #   
  #   actions = [
  #     [:click, "Next Page"],
  #     [:click, ["Option A", "xpath://div[@id='results']/a", "css:.some-button"]] # Will select one randomly
  #   ]
  #   
  #   processor = ScraperUtils::MechanizeActions.new(agent)
  #   result_page = processor.process(page, actions)
  #
  # @example With replacements
  #   replacements = { FROM_DATE: "2022-01-01", TO_DATE: "2022-03-01" }
  #   processor = ScraperUtils::MechanizeActions.new(agent, replacements)
  #   
  #   # Use replacements in actions
  #   actions = [
  #     [:click, "Search between {FROM_DATE} and {TO_DATE}"]
  #   ]
  class MechanizeActions
    # @return [Mechanize] The mechanize agent used for actions
    attr_reader :agent

    # @return [Array] The results of each action performed
    attr_reader :results

    # Initialize a new MechanizeActions processor
    #
    # @param agent [Mechanize] The mechanize agent to use for actions
    # @param replacements [Hash] Optional text replacements to apply to action parameters
    def initialize(agent, replacements = {})
      @agent = agent
      @replacements = replacements || {}
      @results = []
    end

    # Process a sequence of actions on a page
    #
    # @param page [Mechanize::Page] The starting page
    # @param actions [Array<Array>] The sequence of actions to perform
    # @return [Mechanize::Page] The resulting page after all actions
    # @raise [ArgumentError] If an unknown action type is provided
    #
    # @example Action format
    #   actions = [
    #     [:click, "Link Text"],                     # Click on link with this text
    #     [:click, ["Option A", "text:Option B"]],   # Click on one of these options (randomly selected)
    #     [:click, "css:.some-button"],              # Use CSS selector
    #     [:click, "xpath://div[@id='results']/a"],  # Use XPath selector
    #     [:block, ->(page, args, agent, results) { [page, { custom_results: 'data' }] }] # Custom block
    #   ]
    def process(page, actions)
      @results = []
      current_page = page

      actions.each do |action|
        args = action.dup
        action_type = args.shift
        current_page, result =
          case action_type
          when :click
            handle_click(current_page, args)
          when :block
            handle_block(current_page, args)
          else
            raise ArgumentError, "Unknown action type: #{action_type}"
          end

        @results << result
      end

      current_page
    end

    private

    # Process a block action
    #
    # @param page [Mechanize::Page] The current page
    # @param args [Array] The block and its arguments
    # @return [Array<Mechanize::Page, Hash>] The resulting page and status
    def handle_block(page, args)
      block = args.shift
      # Apply replacements to all remaining arguments
      processed_args = args.map { |arg| apply_replacements(arg) }
      block.call(page, processed_args.first, agent, @results.dup)
    end

    # Handle a click action
    #
    # @param page [Mechanize::Page] The current page
    # @param args [Array] The first element is the selection target
    # @return [Array<Mechanize::Page, Hash>] The resulting page and status
    def handle_click(page, args)
      target = args.shift
      if target.is_a?(Array)
        target = ScraperUtils::CycleUtils.pick(target, date: @replacements[:TODAY])
      end
      target = apply_replacements(target)
      element = select_element(page, target)
      if element.nil?
        raise "Unable to find click target: #{target}"
      end

      result = { action: :click, target: target }
      next_page = element.click
      [next_page, result]
    end

    # Select an element on the page based on selector string
    #
    # @param page [Mechanize::Page] The page to search in
    # @param selector_string [String] The selector string, optionally with "css:", "xpath:" or "text:" prefix
    # @return [Mechanize::Element, nil] The selected element or nil if not found
    def select_element(page, selector_string)
      # Handle different selector types based on prefixes
      if selector_string.start_with?("css:")
        selector = selector_string.sub(/^css:/, '')
        # We need to convert Nokogiri elements to Mechanize elements for clicking
        css_element = page.at_css(selector)
        return nil unless css_element
        
        # If it's a link, find the matching Mechanize link
        if css_element.name.downcase == 'a' && css_element['href']
          return page.links.find { |link| link.href == css_element['href'] }
        end
        
        return css_element
      elsif selector_string.start_with?("xpath:")
        selector = selector_string.sub(/^xpath:/, '')
        # We need to convert Nokogiri elements to Mechanize elements for clicking
        xpath_element = page.at_xpath(selector)
        return nil unless xpath_element
        
        # If it's a link, find the matching Mechanize link
        if xpath_element.name.downcase == 'a' && xpath_element['href']
          return page.links.find { |link| link.href == xpath_element['href'] }
        end
        
        return xpath_element
      else
        # Default to text: for links
        selector = selector_string.sub(/^text:/, '')
        # Find links that include the text and don't have fragment-only hrefs
        matching_links = page.links.select do |l|
          l.text.include?(selector) &&
            !(l.href.nil? || l.href.start_with?('#'))
        end

        if matching_links.empty?
          # try case-insensitive
          selector = selector.downcase
          matching_links = page.links.select do |l|
            l.text.downcase.include?(selector) &&
              !(l.href.nil? || l.href.start_with?('#'))
          end
        end

        # Get the link with the a. shortest (closest matching) text and then b. the longest href
        matching_links.min_by { |l| [l.text.strip.length, -l.href.length] }
      end
    end

    # Apply text replacements to a string
    #
    # @param text [String, Object] The text to process or object to return unchanged
    # @return [String, Object] The processed text with replacements or original object
    def apply_replacements(text)
      result = text.to_s

      @replacements.each do |key, value|
        result = result.gsub(/\{#{key}\}/, value.to_s)
      end
      result
    end
  end
end
