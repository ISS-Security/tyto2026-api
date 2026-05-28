# frozen_string_literal: true

module Tyto
  # Maps verified Google OIDC id_token claims onto Tyto account fields. This is
  # the *only* Google-specific piece of the SSO flow: swap this mapper (and the
  # verifier) for another provider and FindOrCreateSsoAccount is unchanged.
  class GoogleAccount
    def initialize(claims)
      @claims = claims
    end

    def provider    = 'google'
    def external_id = @claims['sub']
    def email       = @claims['email']
    def name        = @claims['name']
    def avatar      = @claims['picture']

    # Google sends a real boolean; tolerate the string form some providers use.
    def email_verified?
      [true, 'true'].include?(@claims['email_verified'])
    end

    def to_h
      { provider:, external_id:, email:, email_verified: email_verified?,
        name:, avatar: }
    end
  end
end
