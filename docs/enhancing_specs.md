# Enhancing specs

ScraperUtils provides two methods to help with checking results

* `ScraperUtils::SpecSupport.geocodable?`
* `ScraperUtils::SpecSupport.reasonable_description?`

## Example Code:

```ruby
# frozen_string_literal: true

require "timecop"
require_relative "../scraper"

RSpec.describe Scraper do
  describe ".scrape" do
    def test_scrape(authority)
      ScraperWiki.close_sqlite
      FileUtils.rm_f("data.sqlite")

      VCR.use_cassette(authority) do
        date = Date.new(2025, 4, 15)
        Timecop.freeze(date) do
          Scraper.scrape([authority], 1)
        end
      end

      expected = if File.exist?("spec/expected/#{authority}.yml")
                   YAML.safe_load(File.read("spec/expected/#{authority}.yml"))
                 else
                   []
                 end
      results = ScraperWiki.select("* from data order by council_reference")

      ScraperWiki.close_sqlite

      if results != expected
        # Overwrite expected so that we can compare with version control
        # (and maybe commit if it is correct)
        File.open("spec/expected/#{authority}.yml", "w") do |f|
          f.write(results.to_yaml)
        end
      end

      expect(results).to eq expected

      geocodable = results
                     .map { |record| record["address"] }
                     .uniq
                     .count { |text| ScraperUtils::SpecSupport.geocodable? text }
      puts "Found #{geocodable} out of #{results.count} unique geocodable addresses " \
        "(#{(100.0 * geocodable / results.count).round(1)}%)"
      expect(geocodable).to be > (0.7 * results.count)

      descriptions = results
                       .map { |record| record["description"] }
                       .uniq
                       .count do |text|
        selected = ScraperUtils::SpecSupport.reasonable_description? text
        puts "  description: #{text} is not reasonable" if ENV["DEBUG"] && !selected
        selected
      end
      puts "Found #{descriptions} out of #{results.count} unique reasonable descriptions " \
             "(#{(100.0 * descriptions / results.count).round(1)}%)"
      expect(descriptions).to be > (0.55 * results.count)

      info_urls = results
                  .map { |record| record["info_url"] }
                  .uniq
                  .count { |text| text.to_s.match(%r{\Ahttps?://}) }
      puts "Found #{info_urls} out of #{results.count} unique info_urls " \
             "(#{(100.0 * info_urls / results.count).round(1)}%)"
      expect(info_urls).to be > (0.7 * results.count) if info_urls != 1

      VCR.use_cassette("#{authority}.info_urls") do
        results.each do |record|
          info_url = record["info_url"]
          puts "Checking info_url #{info_url} #{info_urls > 1 ? ' has expected details' : ''} ..."
          response = Net::HTTP.get_response(URI(info_url))

          expect(response.code).to eq("200")
          # If info_url is the same for all records, then it won't have details
          break if info_urls == 1

          expect(response.body).to include(record["council_reference"])
          expect(response.body).to include(record["address"])
          expect(response.body).to include(record["description"])
        end
      end
    end

    Scraper.selected_authorities.each do |authority|
      it authority do
        test_scrape(authority)
      end
    end
  end
end

```
