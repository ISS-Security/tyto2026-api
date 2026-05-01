# frozen_string_literal: true

source 'https://rubygems.org'

# Web API
gem 'base64'
gem 'json'
gem 'logger', '~> 1.0'
gem 'puma', '~>7.0'
gem 'roda', '~>3.0'

# Configuration
gem 'figaro', '~>1.2'
gem 'rake'

# Security
gem 'rbnacl', '~>7.1'

# Database
gem 'sequel', '~>5.55'
gem 'table_print', '~>1.0' # Console / REPL formatting (dev only)

# Debugging
gem 'pry'

group :development, :test do
  gem 'rack-test'
  gem 'sequel-seed', '~>1.1'
  gem 'sqlite3', '~>2.0'
end

group :test do
  gem 'minitest'
  gem 'minitest-rg'
end

group :development do
  gem 'bundler-audit'
  gem 'rerun'
  gem 'rubocop'
  gem 'rubocop-minitest'
  gem 'rubocop-performance'
  gem 'rubocop-rake'
  gem 'rubocop-sequel'
end
