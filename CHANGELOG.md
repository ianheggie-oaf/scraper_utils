# Changelog

## 0.10.2 - 2026-02-09

* Added `ScraperUtils::MiscUtils.throttle_block` as documented in `docs/misc_utilities.md` for use with HTTParty

## 0.10.1 - 2026-01-27

* Added  `ScraperUtils::DbUtils.cleanup_old_records` to Clean up records older than 30 days and approx once a month
  vacuum the DB
* Pauses the request time plus 0.5 seconds
* Removed reference to random delay – it's either not required or it's not enough to make a difference

## 0.9.2 - 2026-01-27

* Removed Emoticons as they are four byte UTF-8 and some databases are configured to only store 3 byte UTF-8

## 0.9.1 - 2025-07-11

* Revert VCR to using `<authority>_info_urls.yml` for VCR cassette cache of `info_urls` check

## 0.9.0 - 2025-07-11

**Significant cleanup - removed code we ended up not using as none of the councils are actually concerned about server load**

* Refactored example code into simple callable methods
* Expand test for geocodeable addresses to include comma between postcode and state at the end of the address.

### Added
- `ScraperUtils::SpecSupport.validate_addresses_are_geocodable!` - validates percentage of geocodable addresses
- `ScraperUtils::SpecSupport.validate_descriptions_are_reasonable!` - validates percentage of reasonable descriptions
- `ScraperUtils::SpecSupport.validate_uses_one_valid_info_url!` - validates single global info_url usage and availability
- `ScraperUtils::SpecSupport.validate_info_urls_have_expected_details!` - validates info_urls contain expected content
- `ScraperUtils::MathsUtils.fibonacci_series` - generates fibonacci sequence up to max value
- `bot_check_expected` parameter to info_url validation methods for handling reCAPTCHA/Cloudflare protection
- Experimental Parallel Processing support
  - Uses the parallel gem with subprocesses
  - Added facility to collect records in memory
  - see docs/parallel_scrapers.md and docs/example_parallel_scraper.rb
- .editorconfig as an example for scrapers

### Fixed
- Typo in `geocodable?` method debug output (`has_suburb_stats` → `has_suburb_states`)
- Code example in `docs/enhancing_specs.md`

### Updated
- `ScraperUtils::SpecSupport.acceptable_description?` - Accept 1 or 2 word descriptors with planning specific terms
- Code example in `docs/enhancing_specs.md` to reflect new support methods
- Code examples
- geocodeable? test is simpler - it requires
  - a street type
  - an uppercase word (assumed to be a suburb) or postcode and
  - a state
- Support for 1 or 2 word "reasonable" descriptions that use words specific to planning alerts
- Added extra street types

### Removed
- Unsued CycleUtils
- Unused DateRangeUtils
- Unused RandomizeUtils
- Unused Scheduling (Fiber and Threads)
- Unused Compliant mode, delays for Agent (Agent is configured with an agent string)
- Unused MechanizeActions

## 0.8.2 - 2025-05-07

* Ignore blank dates supplied when validating rather than complain they are not valid

## 0.8.1 - 2025-05-06

* Removed debugging output accidentally left in

## 0.8.0 - 2025-05-06

* Added ScraperUtils::LogUtils.project_backtrace_line to provide the first project related backtrace line
* Included this summarized line in ScraperUtils::LogUtils.report_on_results report
* Allow upto 250 character error message (was max 50)

## 0.7.2 - 2025-04-15

* Accept postcode before state as well as after

## 0.7.1 - 2025-04-15

* Accept mixed case suburb names after a comma as well as uppercase suburb names as geocachable
* Accept more street type abbreviations and check they are on word boundaries

## 0.7.0 - 2025-04-15

* Added Spec helpers and associated doc: `docs/enhancing_specs.md`
  * `ScraperUtils::SpecSupport.geocodable?`
  * `ScraperUtils::SpecSupport.reasonable_description?`

## 0.6.1 - 2025-03-28

* Changed DEFAULT_MAX_LOAD to 50.0 as we are overestimating the load we present as network latency is included
* Correct documentation of spec_helper extra lines
* Fix misc bugs found in use

## 0.6.0 - 2025-03-16

* Add threads for more efficient scraping
* Adjust defaults for more efficient scraping, retaining just response based delays by default
* Correct and simplify date range utilities so everything is checked at least `max_period` days
* Release Candidate for v1.0.0, subject to testing in production

## 0.5.1 - 2025-03-05

* Remove duplicated example code in docs

## 0.5.0 - 2025-03-05

* Add action processing utility

## 0.4.2 - 2025-03-04

* Fix gem require list

## 0.4.1 - 2025-03-04

* Document `ScraperUtils::CycleUtils.pick(values)`

## 0.4.0 - 2025-03-04

* Add Cycle Utils as an alternative to Date range utils
* Update README.md with changed defaults

## 0.3.0 - 2025-03-04

* Add date range utils
* Flush $stdout and $stderr when logging to sync exception output and logging lines
* Break out example code from README.md into docs dir

## 0.2.1 - 2025-02-28

Fixed broken v0.2.0

## 0.2.0 - 2025-02-28

Added FiberScheduler, enabled complient mode with delays by default and simplified usage removing third retry without proxy

## 0.1.0 - 2025-02-23

First release for development


