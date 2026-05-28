# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Tyto::AuthToken' do
  let(:payload) { { 'account_id' => 7, 'username' => 'chen.hsinyi' } }

  it 'SECURITY: should produce a string token from a payload' do
    token = Tyto::AuthToken.new(payload).to_s
    _(token).must_be_kind_of String
    _(token).wont_be_empty
    _(token).wont_include 'chen.hsinyi'
  end

  it 'SECURITY: should round-trip a payload via new then load' do
    token = Tyto::AuthToken.new(payload).to_s
    loaded = Tyto::AuthToken.load(token)
    _(loaded.payload).must_equal payload
  end

  it 'SECURITY: should default to a FULL scope and round-trip it' do
    loaded = Tyto::AuthToken.load(Tyto::AuthToken.new(payload).to_s)
    _(loaded.scope).must_equal Tyto::AuthScope::FULL
  end

  it 'SECURITY: should carry and round-trip an explicit READ_ONLY scope' do
    token = Tyto::AuthToken.new(
      payload, scope: Tyto::AuthScope.new(Tyto::AuthScope::READ_ONLY)
    ).to_s
    _(Tyto::AuthToken.load(token).scope).must_equal Tyto::AuthScope::READ_ONLY
  end

  it 'SECURITY: should raise ExpiredTokenError when reading scope of expired token' do
    loaded = Tyto::AuthToken.load(Tyto::AuthToken.new(payload, -1).to_s)
    _ { loaded.scope }.must_raise Tyto::AuthToken::ExpiredTokenError
  end

  it 'SECURITY: should expose a freshness predicate on a new token' do
    auth_token = Tyto::AuthToken.new(payload)
    _(auth_token.fresh?).must_equal true
    _(auth_token.expired?).must_equal false
  end

  it 'SECURITY: should report expired when expiration has passed' do
    auth_token = Tyto::AuthToken.new(payload, -1)
    _(auth_token.expired?).must_equal true
    _(auth_token.fresh?).must_equal false
  end

  it 'SECURITY: should raise ExpiredTokenError when reading payload of expired token' do
    token = Tyto::AuthToken.new(payload, -1).to_s
    loaded = Tyto::AuthToken.load(token)
    _ { loaded.payload }.must_raise Tyto::AuthToken::ExpiredTokenError
  end

  it 'SECURITY: should raise InvalidTokenError on garbage input' do
    _ { Tyto::AuthToken.load('not-a-real-token') }
      .must_raise Tyto::AuthToken::InvalidTokenError
  end

  it 'SECURITY: should raise InvalidTokenError on tampered token' do
    token = Tyto::AuthToken.new(payload).to_s
    tampered = "#{token[0..-3]}XX"
    _ { Tyto::AuthToken.load(tampered) }
      .must_raise Tyto::AuthToken::InvalidTokenError
  end

  it 'SECURITY: should produce a generate_key string usable by setup' do
    key = Tyto::AuthToken.generate_key
    _(key).must_be_kind_of String
    _(key).wont_be_empty
  end
end
