# frozen_string_literal: true

source "https://rubygems.org"

platform = if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.0.0")
             :heroku16
           elsif Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.3.0")
             :heroku18
           end

ruby case platform
     when :heroku16 then "~> 2.5.8"
     when :heroku18 then "~> 3.2.2"
     else "~> 3.3.7"
     end

gem "mechanize", platform && (platform == :heroku16 ? "~> 2.7.0" : "~> 2.8.5")
gem "nokogiri", platform && (platform == :heroku16 ? "~> 1.11.2" : "~> 1.15.0")
gem "sqlite3", platform && (platform == :heroku16 ? "~> 1.4.0" : "~> 1.6.3")

# Unable to list in gemspec - Include it in your projects Gemfile when using this gem
gem "scraperwiki", git: "https://github.com/openaustralia/scraperwiki-ruby.git",
                   branch: "morph_defaults"

# development and test gems
gem "rake", platform && (platform == :heroku16 ? "~> 12.3.3" : "~> 13.0")
gem "rspec", platform && (platform == :heroku16 ? "~> 3.9.0" : "~> 3.12")
gem "rubocop", platform && (platform == :heroku16 ? "~> 1.28.2" : "~> 1.73")
gem "rubocop-rake", platform && (platform == :heroku16 ? "~> 0.6.0" : "~> 0.7")
gem "rubocop-rspec", platform && (platform == :heroku16 ? "~> 2.10.0" : "~> 3.5")
gem "simplecov", platform && (platform == :heroku16 ? "~> 0.18.0" : "~> 0.22.0")
gem "simplecov-console"
gem "terminal-table"
gem "webmock", platform && (platform == :heroku16 ? "~> 3.14.0" : "~> 3.19.0")
gem "yard"

gemspec
