# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/rg'
require 'yaml'

require_relative 'test_load_all'

TABLES_TO_WIPE = %i[
  events locations enrollments accounts_roles accounts courses
].freeze

def wipe_database
  TABLES_TO_WIPE.each { |table| app.DB[table].delete }
end

DATA = {} # rubocop:disable Style/MutableConstant
DATA[:courses] = YAML.safe_load_file('db/seeds/course_seeds.yml')
DATA[:locations] = YAML.safe_load_file('db/seeds/location_seeds.yml')
DATA[:events] = YAML.safe_load_file(
  'db/seeds/event_seeds.yml',
  permitted_classes: [Time]
)
DATA[:accounts] = YAML.safe_load_file('db/seeds/accounts_seed.yml')
DATA[:enrollments] = YAML.safe_load_file('db/seeds/enrollments_seed.yml')
