# frozen_string_literal: true

require 'json'

module Tyto
  # Verify a Google-signed id_token, resolve it to a Tyto account, and issue a
  # FULL-scope auth token. The API trusts the *cryptographic* signature on the
  # id_token (verified against Google's JWKS) -- it never sees the user's Google
  # password and makes no userinfo callback.
  class AuthenticateSso
    def self.call(id_token)
      claims = GoogleIdToken.verify(id_token)
      account = FindOrCreateSsoAccount.call(**GoogleAccount.new(claims).to_h)

      AuthorizedAccount.new(
        envelope_for(account), AuthScope.new(AuthScope::FULL), account_id: account.id
      ).to_h
    end

    # Mirror AuthenticateAccount: a login response carries the actor-scoped
    # capabilities the App reads (`current_account.admin?` etc.).
    def self.envelope_for(account)
      envelope = JSON.parse(account.to_json)
      envelope['capabilities'] = AccountPolicy.new(account).capabilities
      envelope
    end
  end
end
