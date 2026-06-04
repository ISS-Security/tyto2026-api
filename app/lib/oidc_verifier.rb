# frozen_string_literal: true

require 'jwt'
require 'json'
require 'http'

module Tyto
  # Generic OpenID Connect id_token verifier.
  #
  # Verifies a provider-signed JWT the way every OIDC provider expects:
  #   1. read the token header to learn which key (`kid`) signed it;
  #   2. fetch the provider's JSON Web Key Set (JWKS) and pick that key;
  #   3. verify the RS256 signature with the key (delegated to the OpenSSL-backed
  #      `jwt` gem -- RbNaCl can't do RSA, and the *provider* dictates the alg);
  #   4. validate the `iss` / `aud` / `exp` claims ourselves.
  #
  # Parameterized by (jwks_uri, audience, allowed_issuers) so any OIDC provider
  # works -- `GoogleIdToken` is just a pre-configured instance. JWKS keys are
  # cached by `kid` and re-fetched on a miss, so provider key rotation is
  # handled transparently.
  class OidcVerifier
    class VerificationError < StandardError; end

    def initialize(jwks_uri:, audience:, allowed_issuers:)
      @jwks_uri = jwks_uri
      @audience = audience
      @allowed_issuers = Array(allowed_issuers)
      @keys_by_kid = {}
    end

    # Returns the verified claims hash, or raises VerificationError.
    def verify(id_token)
      raise VerificationError, 'Missing id_token' if id_token.to_s.empty?

      claims, = JWT.decode(
        id_token, signing_key(key_id(id_token)), true,
        algorithms: ['RS256'], verify_expiration: true
      )
      validate_claims!(claims)
      claims
    rescue JWT::DecodeError => e
      raise VerificationError, "Invalid id_token: #{e.message}"
    end

    private

    # Decode the header without verifying, just to read the signing key id.
    def key_id(id_token)
      _, header = JWT.decode(id_token, nil, false)
      header['kid'] or raise VerificationError, 'id_token header has no kid'
    end

    # Resolve a kid to its OpenSSL public key, (re)fetching the JWKS on a miss.
    def signing_key(kid)
      @keys_by_kid[kid] || refresh_keys[kid] ||
        raise(VerificationError, "No JWKS key for kid #{kid}")
    end

    def refresh_keys
      response = HTTP.get(@jwks_uri)
      raise VerificationError, 'Could not fetch JWKS' unless response.status.success?

      keys = JSON.parse(response.to_s).fetch('keys')
      @keys_by_kid = keys.to_h { |jwk| [jwk['kid'], JWT::JWK.import(jwk).verify_key] }
    end

    def validate_claims!(claims)
      raise VerificationError, "Untrusted issuer: #{claims['iss']}" \
        unless @allowed_issuers.include?(claims['iss'])
      raise VerificationError, 'Audience mismatch' unless claims['aud'] == @audience
    end
  end
end
