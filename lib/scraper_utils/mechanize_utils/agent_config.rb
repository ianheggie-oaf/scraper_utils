# frozen_string_literal: true

require "mechanize"
require "ipaddr"

module ScraperUtils
  module MechanizeUtils
    # Configuration for a Mechanize agent with sensible defaults and configurable settings.
    # Supports global configuration through {.configure} and per-instance overrides.
    #
    # @example Setting global defaults
    #   ScraperUtils::MechanizeUtils::AgentConfig.configure do |config|
    #     config.default_timeout = 90
    #     config.default_random_delay = 5
    #   end
    #
    # @example Creating an instance with defaults
    #   config = ScraperUtils::MechanizeUtils::AgentConfig.new
    #
    # @example Overriding specific settings
    #   config = ScraperUtils::MechanizeUtils::AgentConfig.new(
    #     timeout: 120,
    #     random_delay: 10
    #   )
    class AgentConfig
      DEFAULT_TIMEOUT = 60
      DEFAULT_RANDOM_DELAY = 0
      DEFAULT_MAX_LOAD = 33.3
      MAX_LOAD_CAP = 50.0

      # Class-level defaults that can be modified
      class << self
        # @return [Integer] Default timeout in seconds for agent connections
        attr_accessor :default_timeout

        # @return [Boolean] Default setting for compliance with headers and robots.txt
        attr_accessor :default_compliant_mode

        # @return [Integer, nil] Default average random delay in seconds
        attr_accessor :default_random_delay

        # @return [Float, nil] Default maximum server load percentage (nil = no response delay)
        attr_accessor :default_max_load

        # @return [Boolean] Default setting for SSL certificate verification
        attr_accessor :default_disable_ssl_certificate_check

        # @return [Boolean] Default flag for Australian proxy preference
        attr_accessor :default_australian_proxy

        # @return [String, nil] Default Mechanize user agent
        attr_accessor :default_user_agent

        # Configure default settings for all AgentConfig instances
        # @yield [self] Yields self for configuration
        # @example
        #   AgentConfig.configure do |config|
        #     config.default_timeout = 90
        #     config.default_random_delay = 5
        #     config.default_max_load = 15
        #   end
        # @return [void]
        def configure
          yield self if block_given?
        end

        # Reset all configuration options to their default values
        # @return [void]
        def reset_defaults!
          @default_timeout = ENV.fetch('MORPH_TIMEOUT', DEFAULT_TIMEOUT).to_i # 60
          @default_compliant_mode = ENV.fetch('MORPH_NOT_COMPLIANT', nil).to_s.empty? # true
          @default_random_delay = ENV.fetch('MORPH_RANDOM_DELAY', DEFAULT_RANDOM_DELAY).to_i # 5
          @default_max_load = ENV.fetch('MORPH_MAX_LOAD', DEFAULT_MAX_LOAD).to_f # 33.3
          @default_disable_ssl_certificate_check = !ENV.fetch('MORPH_DISABLE_SSL_CHECK', nil).to_s.empty? # false
          @default_australian_proxy = !ENV.fetch('MORPH_USE_PROXY', nil).to_s.empty? # false
          @default_user_agent = ENV.fetch('MORPH_USER_AGENT', nil) # Uses Mechanize user agent
        end
      end

      # Set defaults on load
      reset_defaults!

      # @return [String] User agent string
      attr_reader :user_agent

      # Give access for testing

      attr_reader :max_load, :random_range

      # Creates Mechanize agent configuration with sensible defaults overridable via configure
      # @param timeout [Integer, nil] Timeout for agent connections (default: 60)
      # @param compliant_mode [Boolean, nil] Comply with headers and robots.txt (default: true)
      # @param random_delay [Integer, nil] Average random delay in seconds (default: 3)
      # @param max_load [Float, nil] Maximum server load percentage (nil = no delay, default: 20%)
      #                              When compliant_mode is true, max_load is capped at 33%
      # @param disable_ssl_certificate_check [Boolean, nil] Skip SSL verification (default: false)
      # @param australian_proxy [Boolean, nil] Use proxy if available (default: false)
      # @param user_agent [String, nil] Configure Mechanize user agent
      def initialize(timeout: nil,
                     compliant_mode: nil,
                     random_delay: nil,
                     max_load: nil,
                     disable_ssl_certificate_check: nil,
                     australian_proxy: nil,
                     user_agent: nil)
        @timeout = timeout.nil? ? self.class.default_timeout : timeout
        @compliant_mode = compliant_mode.nil? ? self.class.default_compliant_mode : compliant_mode
        @random_delay = random_delay.nil? ? self.class.default_random_delay : random_delay
        @max_load = max_load.nil? ? self.class.default_max_load : max_load
        @max_load = [@max_load || DEFAULT_MAX_LOAD, MAX_LOAD_CAP].min if @compliant_mode
        @user_agent = user_agent.nil? ? self.class.default_user_agent : user_agent

        @disable_ssl_certificate_check = if disable_ssl_certificate_check.nil?
                                           self.class.default_disable_ssl_certificate_check
                                         else
                                           disable_ssl_certificate_check
                                         end
        @australian_proxy = if australian_proxy.nil?
                              self.class.default_australian_proxy
                            else
                              australian_proxy
                            end

        # Validate proxy URL format if proxy will be used
        @australian_proxy &&= !ScraperUtils.australian_proxy.to_s.empty?
        if @australian_proxy
          uri = begin
                  URI.parse(ScraperUtils.australian_proxy.to_s)
                rescue URI::InvalidURIError => e
                  raise URI::InvalidURIError, "Invalid proxy URL format: #{e.message}"
                end
          unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
            raise URI::InvalidURIError, "Proxy URL must start with http:// or https://"
          end
          unless uri.host && uri.port
            raise URI::InvalidURIError, "Proxy URL must include host and port"
          end
        end

        if @random_delay&.positive?
          min_random = Math.sqrt(@random_delay * 3.0 / 13.0)
          @random_range = min_random.round(3)..(3 * min_random).round(3)
        end

        today = Date.today.strftime("%Y-%m-%d")
        @user_agent = ENV.fetch("MORPH_USER_AGENT", nil)&.sub("TODAY", today)
        if @compliant_mode
          version = ScraperUtils::VERSION
          @user_agent ||= "Mozilla/5.0 (compatible; ScraperUtils/#{version} #{today}; +https://github.com/ianheggie-oaf/scraper_utils)"
        end

        @robots_checker = RobotsChecker.new(@user_agent) if @user_agent
        @adaptive_delay = AdaptiveDelay.new(max_load: @max_load) if @max_load
        display_options
      end

      # Configures a Mechanize agent with these settings
      # @param agent [Mechanize] The agent to configure
      # @return [void]
      def configure_agent(agent)
        agent.verify_mode = OpenSSL::SSL::VERIFY_NONE if @disable_ssl_certificate_check

        if @timeout
          agent.open_timeout = @timeout
          agent.read_timeout = @timeout
        end
        if @compliant_mode
          agent.user_agent = user_agent
          agent.request_headers ||= {}
          agent.request_headers["Accept"] =
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
          agent.request_headers["Upgrade-Insecure-Requests"] = "1"
        end
        if @australian_proxy
          agent.agent.set_proxy(ScraperUtils.australian_proxy)
          agent.request_headers["Accept-Language"] = "en-AU,en-US;q=0.9,en;q=0.8"
          verify_proxy_works(agent)
        end

        agent.pre_connect_hooks << method(:pre_connect_hook)
        agent.post_connect_hooks << method(:post_connect_hook)
      end

      private

      def display_options
        display_args = []
        display_args << "timeout=#{@timeout}" if @timeout
        display_args << if ScraperUtils.australian_proxy.to_s.empty? && !@australian_proxy
                          "#{ScraperUtils::AUSTRALIAN_PROXY_ENV_VAR} not set"
                        else
                          "australian_proxy=#{@australian_proxy.inspect}"
                        end
        display_args << "compliant_mode" if @compliant_mode
        display_args << "random_delay=#{@random_delay}" if @random_delay
        display_args << "max_load=#{@max_load}%" if @max_load
        display_args << "disable_ssl_certificate_check" if @disable_ssl_certificate_check
        display_args << "default args" if display_args.empty?
        ScraperUtils::LogUtils.log(
          "Configuring Mechanize agent with #{display_args.join(', ')}"
        )
      end

      def pre_connect_hook(_agent, request)
        @connection_started_at = Time.now
        return unless DebugUtils.verbose?

        ScraperUtils::LogUtils.log(
          "Pre Connect request: #{request.inspect} at #{@connection_started_at}"
        )
      end

      def post_connect_hook(_agent, uri, response, _body)
        raise ArgumentError, "URI must be present in post-connect hook" unless uri

        response_time = Time.now - @connection_started_at
        if DebugUtils.basic?
          ScraperUtils::LogUtils.log(
            "Post Connect uri: #{uri.inspect}, response: #{response.inspect} " \
              "after #{response_time} seconds"
          )
        end

        if @robots_checker&.disallowed?(uri)
          raise ScraperUtils::UnprocessableSite,
                "URL is disallowed by robots.txt specific rules: #{uri}"
        end

        @delay_till = nil
        @delay = @robots_checker&.crawl_delay&.round(3)
        debug_msg = "Delaying robots.txt: crawl_delay #{@delay} seconds"
        unless @delay&.positive?
          delays = {
            max_load: @adaptive_delay&.next_delay(uri, response_time)&.round(3),
            random: (@random_range ? (rand(@random_range) ** 2).round(3) : nil)
          }
          @delay = [delays[:max_load], delays[:random]].compact.sum
          debug_msg = "Delaying #{@delay} seconds, sum of: #{delays.inspect}"
        end
        if @delay&.positive?
          @delay_till = Time.now + @delay
          ScraperUtils::LogUtils.log(debug_msg) if ScraperUtils::DebugUtils.basic?
        end
        response
      end

      def verify_proxy_works(agent)
        $stderr.flush
        $stdout.flush
        LogUtils.log "Checking proxy works..."
        my_ip = MechanizeUtils.public_ip(agent)
        begin
          IPAddr.new(my_ip)
        rescue IPAddr::InvalidAddressError => e
          raise "Invalid public IP address returned by proxy check: #{my_ip.inspect}: #{e}"
        end
        ScraperUtils::LogUtils.log "Proxy is using IP address: #{my_ip.inspect}"
        my_headers = MechanizeUtils.public_headers(agent)
        begin
          # Check response is JSON just to be safe!
          headers = JSON.parse(my_headers)
          puts "Proxy is passing headers:"
          puts JSON.pretty_generate(headers["headers"])
        rescue JSON::ParserError => e
          puts "Couldn't parse public_headers: #{e}! Raw response:"
          puts my_headers.inspect
        end
      rescue Timeout::Error => e # Includes Net::OpenTimeout
        raise "Proxy check timed out: #{e}"
      rescue Errno::ECONNREFUSED, Net::HTTP::Persistent::Error => e
        raise "Failed to connect to proxy: #{e}"
      rescue Mechanize::ResponseCodeError => e
        raise "Proxy check error: #{e}"
      end
    end
  end
end
