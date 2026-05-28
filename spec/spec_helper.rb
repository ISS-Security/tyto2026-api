# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/rg'
require 'yaml'

require_relative 'test_load_all'

TABLES_TO_WIPE = %i[
  attendances events locations enrollments accounts_roles accounts courses
].freeze

def wipe_database
  TABLES_TO_WIPE.each { |table| app.DB[table].delete }
end

# Builds an Authorization: Bearer header for the given account, mirroring
# the encrypted-envelope shape AuthenticateAccount issues at login.
def auth_header(account)
  auth_header_with_scope(account, Tyto::AuthScope::FULL)
end

# Bearer header whose token carries an explicit AuthScope -- used to exercise
# READ_ONLY ("API key") enforcement at the HTTP boundary.
def auth_header_with_scope(account, scope)
  envelope = JSON.parse(account.to_json)
  envelope['attributes'] = envelope['attributes'].merge('id' => account.id)
  token = Tyto::AuthToken.new(envelope, scope: Tyto::AuthScope.new(scope)).to_s
  { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
end

def auth_request_header(account)
  auth_header(account).merge('CONTENT_TYPE' => 'application/json')
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
