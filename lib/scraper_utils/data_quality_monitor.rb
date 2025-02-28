# frozen_string_literal: true

module ScraperUtils
  # Monitors data quality during scraping by tracking successful vs failed record processing
  # Automatically triggers an exception if the error rate exceeds a threshold
  class DataQualityMonitor
    # Get the statistics for all authorities
    # @return [Hash, nil] Hash of statistics per authority or nil if none started
    class << self
      attr_reader :stats
    end

    # Notes the start of processing an authority and clears any previous stats
    #
    # @param authority_label [Symbol] The authority we are processing
    # @return [void]
    def self.start_authority(authority_label)
      @stats ||= {}
      @authority_label = authority_label
      @stats[@authority_label] = { saved: 0, unprocessed: 0 }
    end

    def self.threshold
      5.01 + (@stats[@authority_label][:saved] * 0.1) if @stats&.fetch(@authority_label, nil)
    end

    # Logs an unprocessable record and raises an exception if error threshold is exceeded
    # The threshold is 5 + 10% of saved records
    #
    # @param exception [Exception] The exception that caused the record to be unprocessable
    # @param record [Hash, nil] The record that couldn't be processed
    # @raise [ScraperUtils::UnprocessableSite] When too many records are unprocessable
    # @return [void]
    def self.log_unprocessable_record(exception, record)
      start_authority(:"") unless @stats
      @stats[@authority_label][:unprocessed] += 1
      ScraperUtils::FiberScheduler.log "Erroneous record #{@authority_label} - #{record&.fetch(
        'address', nil
      ) || record.inspect}: #{exception}"
      return unless @stats[@authority_label][:unprocessed] > threshold

      raise ScraperUtils::UnprocessableSite,
            "Too many unprocessable_records for #{@authority_label}: " \
            "#{@stats[@authority_label].inspect} - aborting processing of site!"
    end

    # Logs a successfully saved record
    #
    # @param record [Hash] The record that was saved
    # @return [void]
    def self.log_saved_record(record)
      start_authority(:"") unless @stats
      @stats[@authority_label][:saved] += 1
      ScraperUtils::FiberScheduler.log "Saving record #{@authority_label} - #{record['address']}"
    end
  end
end
