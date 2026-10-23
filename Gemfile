# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in lowdata.gemspec
gemspec

group :development do
  gem 'irb'
  gem 'rack'
  gem 'rack-test'
  gem 'rake', '~> 13.0'
  gem 'rspec', '~> 3.0'
  gem 'rubocop', require: false
  gem 'sqlite3'
end

# Drivers for running the specs on Postgres and MySQL. Install with: bundle config set --local with databases
group :databases, optional: true do
  gem 'pg'
  gem 'trilogy'
end
