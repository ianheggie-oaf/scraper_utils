# frozen_string_literal: true

module ScraperUtils
  module MechanizeUtils
    # robots.txt checker with deliberately simplistic rules
    class RobotsChecker
      # @return [String] Lowercased user_agent for matching
      attr_reader :user_agent

      # Initialize with full user agent string like:
      # "Mozilla/5.0 (compatible; ScraperUtils/0.1.0 2025-02-22; +https://github.com/ianheggie-oaf/scraper_utils)"
      # Extracts the bot name (e.g. "ScraperUtils") to check against robots.txt
      # Checks for
      # * Disallow for User-agent: bot_name and
      # * Crawl-delay from either User-agent: bot name or * (default)
      def initialize(user_agent)
        @user_agent = extract_user_agent(user_agent).downcase
        if DebugUtils.basic?
          ScraperUtils::LogUtils.log(
            "Checking robots.txt for user agent prefix: #{@user_agent} (case insensitive)"
          )
        end
        @rules = {} # domain -> {rules: [], delay: int}
        @delay = nil # Delay from last robots.txt check
      end

      # Check if a URL is disallowed based on robots.txt rules specific to our user agent
      # @param url [String] The full URL to check
      # @return [Boolean] true if specifically blocked for our user agent, otherwise false
      def disallowed?(url)
        return false unless url

        uri = URI(url)
        domain = "#{uri.scheme}://#{uri.host}"
        path = uri.path || "/"

        # Get or fetch robots.txt rules
        rules = get_rules(domain)
        return false unless rules # If we can't get robots.txt, assume allowed

        # Store any delay found for this domain
        @delay = rules[:our_delay]

        # Check rules specific to our user agent
        matches_any_rule?(path, rules[:our_rules])
      end

      # Returns the crawl delay (if any) that applied to the last URL checked
      # Should be called after disallowed? to get relevant delay
      # @return [Integer, nil] The delay in seconds, or nil if no delay specified
      def crawl_delay
        @delay
      end

      private

      def extract_user_agent(user_agent)
        if user_agent =~ /^(.*compatible;\s*)?([-_a-z0-9]+)/i
          user_agent = ::Regexp.last_match(2)&.strip
        end
        user_agent&.strip
      end

      def matches_any_rule?(path, rules)
        rules&.any? { |rule| path.start_with?(rule) }
      end

      def get_rules(domain)
        return @rules[domain] if @rules.key?(domain)

        begin
          response = Net::HTTP.get_response(URI("#{domain}/robots.txt"))
          return nil unless response.code.start_with?("2") # 2xx response

          rules = parse_robots_txt(response.body)
          @rules[domain] = rules
          rules
        rescue StandardError => e
          if DebugUtils.basic?
            ScraperUtils::LogUtils.log(
              "WARNING: Failed to fetch robots.txt for #{domain}: #{e.message}"
            )
          end
          nil
        end
      end

      # Parse robots.txt content into structured rules
      # Only collects rules for our specific user agent and generic crawl-delay
      # @param content [String] The robots.txt content
      # @return [Hash] Hash containing :our_rules and :our_delay
      def parse_robots_txt(content)
        sections = [] # Array of {agent:, rules:[], delay:} hashes
        current_section = nil

        content.each_line do |line|
          line = line.strip.downcase
          next if line.empty? || line.start_with?("#")

          if line.start_with?("user-agent:")
            agent = line.split(":", 2).last.strip
            # Check if this is a continuation of the previous section
            if current_section && current_section[:rules].empty? && current_section[:delay].nil?
              current_section[:agents] << agent
            else
              current_section = { agents: [agent], rules: [], delay: nil }
              sections << current_section
            end
            next
          end

          next unless current_section # Skip rules before first user-agent

          if line.start_with?("disallow:")
            path = line.split(":", 2).last.strip
            current_section[:rules] << path unless path.empty?
          elsif line.start_with?("crawl-delay:")
            delay = line.split(":", 2).last.strip.to_i
            current_section[:delay] = delay if delay.positive?
          end
        end

        # Sort sections by most specific agent match first
        matched_section = sections.find do |section|
          section[:agents].any? do |agent|
            # Our user agent starts with the agent from robots.txt
            @user_agent.start_with?(agent) ||
              # Or the agent from robots.txt starts with our user agent
              # (handles ScraperUtils matching ScraperUtils/1.0)
              agent.start_with?(@user_agent)
          end
        end

        # Use matched section or fall back to wildcard
        if matched_section
          {
            our_rules: matched_section[:rules],
            our_delay: matched_section[:delay]
          }
        else
          # Find default section
          default_section = sections.find { |s| s[:agents].include?("*") }
          {
            our_rules: [],
            our_delay: default_section&.dig(:delay)
          }
        end
      end
    end
  end
end
