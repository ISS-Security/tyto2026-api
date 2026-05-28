# frozen_string_literal: true

require 'json'

module Tyto
  # Authorizes a requester to view an account, then returns an
  # AuthorizedAccount carrying the account envelope plus a freshly-minted,
  # `auth_scope`-scoped token. The account-detail endpoint uses this to hand
  # out a READ_ONLY "API key" distinct from the caller's full session token.
  class AuthorizeAccount
    # Raised when the requester may not view the requested account. The
    # controller maps this to 404 so account existence is not leaked.
    class ForbiddenError < StandardError
      def message
        'You are not allowed to access that account'
      end
    end

    def self.call(auth:, username:, auth_scope: AuthScope::READ_ONLY)
      requester = requester_for(auth)
      account = Account.first(username:)
      raise ForbiddenError unless account

      policy = AccountPolicy.new(requester, account)
      raise ForbiddenError unless policy.can_view?

      AuthorizedAccount.new(envelope_for(account, policy, requester), auth_scope, account_id: account.id)
    end

    def self.requester_for(auth)
      requester_id = auth&.account&.dig('attributes', 'id')
      requester_id && Account.first(id: requester_id)
    end

    def self.envelope_for(account, policy, requester)
      envelope = JSON.parse(account.to_json)
      envelope['policies'] = policy.summary
      envelope['capabilities'] = policy.capabilities if requester && requester.id == account.id
      envelope
    end
  end
end
