# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/rg'
require 'yaml'

require_relative 'test_load_all'

TABLES_TO_WIPE = %i[
  attendances events locations enrollments sso_identities accounts_roles accounts courses
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

# SSO test harness: a self-signed RSA key stands in for Google's signing key.
# We expose the matching public JWKS (to WebMock-stub Google's jwks_uri) and a
# helper to mint validly-signed id_tokens, so the suite needs no real Google
# credentials or network access.
require 'openssl'
require 'jwt'

module SsoTestKeys
  KID = 'tyto-test-key'

  module_function

  # Generated once per process, lazily (only when an SSO spec asks for it).
  def signing_key
    @signing_key ||= OpenSSL::PKey::RSA.generate(2048)
  end

  # Public JWKS as Google would publish it (no private key material).
  def jwks
    { keys: [JWT::JWK.new(signing_key, { kid: KID }).export] }
  end

  def default_claims
    {
      'iss' => 'https://accounts.google.com',
      'aud' => ENV.fetch('GOOGLE_CLIENT_ID'),
      'sub' => '110169484474386276334',
      'email' => 'sso-user@example.com',
      'email_verified' => true,
      'name' => 'SSO User',
      'picture' => 'https://lh3.googleusercontent.com/a/sso-user',
      'exp' => Time.now.to_i + 3600
    }
  end

  # Mint a signed id_token. `overrides` patches claims for sad paths; the
  # positional `key` signs with a *different* key to exercise bad-signature
  # rejection. Both are positional so string-keyed override hashes aren't
  # misparsed as keyword arguments.
  def mint_id_token(overrides = {}, key = signing_key)
    JWT.encode(default_claims.merge(overrides), key, 'RS256', { kid: KID })
  end
end
