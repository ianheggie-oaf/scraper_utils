# Changelog

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


