# Example scrape method updated to use ScraperUtils::FibreScheduler

def scrape(authorities, attempt)
  ScraperUtils::FiberScheduler.reset!
  exceptions = {}
  authorities.each do |authority_label|
    ScraperUtils::FiberScheduler.register_operation(authority_label) do
      ScraperUtils::FiberScheduler.log "Collecting feed data for #{authority_label}, attempt: #{attempt}..."
      begin
        ScraperUtils::DataQualityMonitor.start_authority(authority_label)
        YourScraper.scrape(authority_label) do |record|
          begin
            record["authority_label"] = authority_label.to_s
            ScraperUtils::DbUtils.save_record(record)
          rescue ScraperUtils::UnprocessableRecord => e
            ScraperUtils::DataQualityMonitor.log_unprocessable_record(e, record)
            exceptions[authority_label] = e
          end
        end
      rescue StandardError => e
        warn "#{authority_label}: ERROR: #{e}"
        warn e.backtrace
        exceptions[authority_label] = e
      end
    end # end of register_operation block
  end
  ScraperUtils::FiberScheduler.run_all
  exceptions
end
