# frozen_string_literal: true

require "uri"

# Adapts delays between requests based on server response times.
# Target delay is proportional to response time based on max_load setting.
# Uses an exponential moving average to smooth variations in response times.
class AdaptiveDelay
  DEFAULT_MIN_DELAY = 0.0
  DEFAULT_MAX_DELAY = 30.0 # Presumed default timeout for Mechanize

  attr_reader :min_delay, :max_delay, :max_load

  # Creates a new adaptive delay calculator
  #
  # @param min_delay [Float] Minimum delay between requests in seconds
  # @param max_delay [Float] Maximum delay between requests in seconds
  # @param max_load [Float] Maximum load percentage (1-99) we aim to place on the server
  #                         Lower values are more conservative (e.g., 20% = 4x response time delay)
  def initialize(min_delay: DEFAULT_MIN_DELAY, max_delay: DEFAULT_MAX_DELAY, max_load: 20.0)
    @delays = {} # domain -> last delay used
    @min_delay = min_delay.to_f
    @max_delay = max_delay.to_f
    @max_load = max_load.to_f.clamp(1.0, 99.0)
    @response_multiplier = (100.0 - @max_load) / @max_load

    return unless ENV["DEBUG"]

    ScraperUtils::FiberScheduler.log(
      "AdaptiveDelay initialized with delays between #{@min_delay} and #{@max_delay} seconds"
    )
    ScraperUtils::FiberScheduler.log(
      "Using max_load of #{@max_load}% (response multiplier: #{@response_multiplier.round(2)}x)"
    )
  end

  # @param uri [URI::Generic, String] The URL to extract the domain from
  # @return [String] The domain in the format "scheme://host"
  def domain(uri)
    uri = URI(uri) unless uri.is_a?(URI)
    "#{uri.scheme}://#{uri.host}".downcase
  end

  # @param uri [URI::Generic, String] URL to get delay for
  # @return [Float] Current delay for the domain, or min_delay if no delay set
  def delay(uri)
    @delays[domain(uri)] || @min_delay
  end

  # @param uri [URI::Generic, String] URL the response came from
  # @param response_time [Float] Time in seconds the server took to respond
  # @return [Float] The calculated delay to use with the next request
  def next_delay(uri, response_time)
    uris_domain = domain(uri)
    target_delay = (response_time * @response_multiplier).clamp(0.0, @max_delay)
    current_delay = @delays[uris_domain] || target_delay
    delay = ((9.0 * current_delay) + target_delay) / 10.0
    delay = delay.clamp(@min_delay, @max_delay)

    if ENV["DEBUG"]
      ScraperUtils::FiberScheduler.log(
        "Adaptive delay for #{uris_domain} updated to #{delay.round(2)}s (target: " \
        "#{@response_multiplier.round(1)}x response_time of #{response_time.round(2)}s)"
      )
    end

    @delays[uris_domain] = delay
    delay
  end
end
