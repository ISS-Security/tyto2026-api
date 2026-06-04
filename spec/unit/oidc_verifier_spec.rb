# frozen_string_literal: true

require_relative '../spec_helper'
require 'webmock/minitest'

describe 'OidcVerifier' do
  before do
    @jwks_url = 'https://oidc.test/jwks'
    @verifier = Tyto::OidcVerifier.new(
      jwks_uri: @jwks_url,
      audience: ENV.fetch('GOOGLE_CLIENT_ID'),
      allowed_issuers: ['https://accounts.google.com']
    )
    stub_request(:get, @jwks_url).to_return(
      body: SsoTestKeys.jwks.to_json, status: 200,
      headers: { 'content-type' => 'application/json' }
    )
  end

  after { WebMock.reset! }

  it 'HAPPY: verifies a correctly-signed token and returns its claims' do
    claims = @verifier.verify(SsoTestKeys.mint_id_token)

    _(claims['sub']).must_equal SsoTestKeys.default_claims['sub']
    _(claims['email']).must_equal 'sso-user@example.com'
    _(claims['email_verified']).must_equal true
  end

  it 'BAD: rejects a token signed by a key absent from the JWKS' do
    forged = SsoTestKeys.mint_id_token({}, OpenSSL::PKey::RSA.generate(2048))
    _ { @verifier.verify(forged) }.must_raise Tyto::OidcVerifier::VerificationError
  end

  it 'BAD: rejects a token with the wrong audience' do
    _ { @verifier.verify(SsoTestKeys.mint_id_token('aud' => 'someone-else')) }
      .must_raise Tyto::OidcVerifier::VerificationError
  end

  it 'BAD: rejects a token from an untrusted issuer' do
    _ { @verifier.verify(SsoTestKeys.mint_id_token('iss' => 'https://evil.test')) }
      .must_raise Tyto::OidcVerifier::VerificationError
  end

  it 'BAD: rejects an expired token' do
    _ { @verifier.verify(SsoTestKeys.mint_id_token('exp' => Time.now.to_i - 60)) }
      .must_raise Tyto::OidcVerifier::VerificationError
  end

  it 'BAD: rejects a token whose kid is not in the JWKS' do
    unknown = JWT.encode(
      SsoTestKeys.default_claims, SsoTestKeys.signing_key, 'RS256', { kid: 'no-such-kid' }
    )
    _ { @verifier.verify(unknown) }.must_raise Tyto::OidcVerifier::VerificationError
  end

  it 'BAD: rejects a blank or nil token' do
    _ { @verifier.verify('') }.must_raise Tyto::OidcVerifier::VerificationError
    _ { @verifier.verify(nil) }.must_raise Tyto::OidcVerifier::VerificationError
  end

  describe 'GoogleIdToken (configured instance)' do
    before do
      stub_request(:get, Tyto::GoogleIdToken::JWKS_URI).to_return(
        body: SsoTestKeys.jwks.to_json, status: 200,
        headers: { 'content-type' => 'application/json' }
      )
    end

    it 'HAPPY: verifies a Google-issued token against Google JWKS' do
      claims = Tyto::GoogleIdToken.verify(SsoTestKeys.mint_id_token)
      _(claims['sub']).must_equal SsoTestKeys.default_claims['sub']
    end
  end
end
