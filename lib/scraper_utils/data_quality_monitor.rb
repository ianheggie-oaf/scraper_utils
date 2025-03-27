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
    def self.start_authority(authority_label)
      @stats ||= {}
      @stats[authority_label] = { saved: 0, unprocessed: 0 }
    end

    # Extracts authority label and ensures stats are setup for record
    def self.extract_authority(record)
      authority_label = (record&.key?("authority_label") ? record["authority_label"] : "").to_sym
      @stats ||= {}
      @stats[authority_label] ||= { saved: 0, unprocessed: 0 }
      authority_label
    end

    def self.threshold(authority_label)
      5.01 + (@stats[authority_label][:saved] * 0.1) if @stats&.fetch(authority_label, nil)
    end

    # Logs an unprocessable record and raises an exception if error threshold is exceeded
    # The threshold is 5 + 10% of saved records
    #
    # @param exception [Exception] The exception that caused the record to be unprocessable
    # @param record [Hash, nil] The record that couldn't be processed
    # @raise [ScraperUtils::UnprocessableSite] When too many records are unprocessable
    # @return [void]
    def self.log_unprocessable_record(exception, record)
      authority_label = extract_authority(record)
      @stats[authority_label][:unprocessed] += 1
      ScraperUtils::LogUtils.log "Erroneous record #{authority_label} - #{record&.fetch(
        'address', nil
      ) || record.inspect}: #{exception}"
      return unless @stats[authority_label][:unprocessed] > threshold(authority_label)

      raise ScraperUtils::UnprocessableSite,
            "Too many unprocessable_records for #{authority_label}: " \
            "#{@stats[authority_label].inspect} - aborting processing of site!"
    end

    # Logs a successfully saved record
    #
    # @param record [Hash] The record that was saved
    # @return [void]
    def self.log_saved_record(record)
      authority_label = extract_authority(record)
      @stats[authority_label][:saved] += 1
      ScraperUtils::LogUtils.log "Saving record #{authority_label} - #{record['address']}"
    end
  end
end
