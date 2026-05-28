# frozen_string_literal: true

require_relative 'oidc_verifier'

module Tyto
  # Google-configured OIDC verifier. Google signs id_tokens with RS256 and
  # publishes its keys at a stable JWKS URL; the token's `aud` must equal our
  # OAuth client id. Identity claims (`sub`, `email`, `email_verified`, `name`,
  # `picture`) are read straight from the verified token -- no userinfo hop.
  #
  # Note: the verifier deliberately does NOT reject an unverified email. A valid
  # signature always authenticates the identity (`sub`); `email_verified` only
  # gates the email-link step downstream (FindOrCreateSsoAccount).
  class GoogleIdToken
    JWKS_URI = 'https://www.googleapis.com/oauth2/v3/certs'
    # Google has historically issued both forms of the issuer claim.
    ISSUERS = ['https://accounts.google.com', 'accounts.google.com'].freeze

    def self.verify(id_token)
      verifier.verify(id_token)
    end

    # Memoized so the JWKS key cache survives across requests.
    def self.verifier
      @verifier ||= OidcVerifier.new(
        jwks_uri: ENV.fetch('GOOGLE_JWKS_URL', JWKS_URI),
        audience: ENV.fetch('GOOGLE_CLIENT_ID'),
        allowed_issuers: ISSUERS
      )
    end
  end
end
