# frozen_string_literal: true

require 'rake/testtask'
require './require_app'

task :default => :spec

desc 'Tests API specs only'
task :api_spec do
  sh 'ruby spec/api_spec.rb'
end

desc 'Test all the specs'
Rake::TestTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.warning = false
end

desc 'Runs rubocop on tested code'
task style: %i[spec audit] do
  sh 'rubocop .'
end

desc 'Update vulnerabilities list and audit gems'
task :audit do
  sh 'bundle audit check --update'
end

desc 'Checks for release'
task release_check: %i[spec style audit] do
  puts "\nReady for release!"
end

task :print_env do # rubocop:disable Rake/Desc
  puts "Environment: #{ENV['RACK_ENV'] || 'development'}"
end

desc 'Run application console (pry)'
task console: :print_env do
  sh 'pry -r ./spec/test_load_all'
end

namespace :run do
  desc 'Run API in development mode'
  task :dev do
    sh 'puma -p 3000'
  end
end

namespace :db do
  task :load do # rubocop:disable Rake/Desc
    require_app(['config'])
    require 'sequel'

    Sequel.extension :migration
    @app = Tyto::Api
  end

  task :load_models do # rubocop:disable Rake/Desc
    require_app(%w[config models services])
  end

  desc 'Run migrations'
  task migrate: %i[load print_env] do
    puts 'Migrating database to latest'
    Sequel::Migrator.run(@app.DB, 'db/migrations')
  end

  desc 'Destroy data in database; maintain tables'
  task delete: :load_models do
    Tyto::Event.dataset.destroy
    Tyto::Location.dataset.destroy
    Tyto::Enrollment.dataset.destroy
    Tyto::Account.dataset.destroy
    Tyto::Course.dataset.destroy
  end

  desc 'Delete dev or test database file'
  task drop: :load do
    if @app.environment == :production
      puts 'Cannot wipe production database!'
      return
    end

    db_filename = "db/local/#{Tyto::Api.environment}.db"
    FileUtils.rm(db_filename)
    puts "Deleted #{db_filename}"
  end

  task reset_seeds: :load_models do # rubocop:disable Rake/Desc
    db = Tyto::Api.DB
    db[:schema_seeds].delete if db.tables.include?(:schema_seeds)
    Tyto::Event.dataset.destroy
    Tyto::Location.dataset.destroy
    Tyto::Enrollment.dataset.destroy
    db[:accounts_roles].delete
    Tyto::Account.dataset.destroy
    Tyto::Course.dataset.destroy
  end

  desc 'Seeds the development database'
  task seed: :load_models do
    require 'sequel/extensions/seed'
    Sequel::Seed.setup(:development)
    Sequel.extension :seed
    Sequel::Seeder.apply(Tyto::Api.DB, 'db/seeds')
  end
end

desc 'Delete all data and reseed'
task reseed: %i[db:reset_seeds db:seed]

namespace :newkey do
  desc 'Create sample cryptographic key for database'
  task :db do
    require_app('lib', config: false)
    puts "DB_KEY: #{Tyto::SecureDB.generate_key}"
  end

  desc 'Create sample cryptographic key for HMAC lookup hashing'
  task :hash do
    require_app('lib', config: false)
    puts "HASH_KEY: #{Tyto::SecureDB.generate_key}"
  end
end
