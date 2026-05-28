# frozen_string_literal: true

require 'securerandom'

module Tyto
  # Provider-agnostic: resolve a verified SSO login to a Tyto account.
  #
  #   1. Known identity  -> the account already linked to (provider, external_id).
  #   2. Verified email  -> link this identity to the existing account whose
  #                         email matches -- but ONLY when the provider asserts
  #                         the email is verified. An unverified email never
  #                         links (that is the account-takeover guard).
  #   3. Otherwise        -> create a new `member` account + its identity row.
  #
  # Only the verifier + mapper are provider-specific; this service is not.
  class FindOrCreateSsoAccount
    # The provider asserted an *unverified* email that already belongs to
    # another account. We refuse to link it (takeover guard) and cannot create
    # a duplicate (email_hash is unique), so the login is rejected as a conflict.
    class EmailConflictError < StandardError; end

    # Accepts the full mapped claim set; `**` absorbs claims Tyto does not
    # persist (e.g. `name`), keeping the service provider-agnostic.
    # rubocop:disable Metrics/ParameterLists
    def self.call(provider:, external_id:, email:, email_verified:, avatar: nil, **)
      Tyto::Api.DB.transaction do
        account =
          identity_account(provider, external_id) ||
          linkable_account(email, email_verified) ||
          create_member_account(provider:, email:, avatar:)

        link_identity(account, provider, external_id)
        account
      end
    end
    # rubocop:enable Metrics/ParameterLists

    def self.identity_account(provider, external_id)
      SsoIdentity.first(provider:, external_id:)&.account
    end

    def self.linkable_account(email, email_verified)
      return nil unless email_verified && email

      Account.first(email_hash: SecureDB.hash(email))
    end

    def self.create_member_account(provider:, email:, avatar:)
      # Reached only when we declined to link (e.g. unverified email). If that
      # email is already taken, we can neither link nor create a duplicate.
      raise EmailConflictError, email if email && Account.first(email_hash: SecureDB.hash(email))

      account = Account.new(
        username: unique_username(email, provider),
        email:,
        avatar:,
        # Random and never disclosed: an SSO account cannot be password-authed.
        password: SecureDB.generate_key
      )
      account.save_changes
      account.add_system_role(Role.first(name: 'member'))
      account
    end

    # Idempotent: skip if this identity is already linked.
    def self.link_identity(account, provider, external_id)
      return if SsoIdentity.first(provider:, external_id:)

      SsoIdentity.create(account_id: account.id, provider:, external_id:)
    end

    # Username is cosmetic (identity is keyed elsewhere). Derive it from the
    # email local-part, suffixing `@<provider>` only on collision.
    def self.unique_username(email, provider)
      base = email.to_s.split('@').first
      base = provider if base.to_s.empty?
      return base unless Account.first(username: base)

      suffixed = "#{base}@#{provider}"
      return suffixed unless Account.first(username: suffixed)

      "#{suffixed}-#{SecureRandom.hex(3)}"
    end
  end
end
