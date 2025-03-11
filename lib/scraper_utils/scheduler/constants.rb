module ScraperUtils
  module Scheduler
    module Constants
      MAIN_FIBER = Fiber.current

      # @!group Scheduler defaults
      DEFAULT_MAX_WORKERS = 50
      DEFAULT_TIMEOUT = 6 * 60 * 60 # 6 hours
      POLL_PERIOD = 0.01
    end
  end
end
