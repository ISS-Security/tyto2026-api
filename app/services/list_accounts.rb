# frozen_string_literal: true

require 'json'

module Tyto
  # Lists every account for an admin requester (the App's Members page),
  # with optional role filter / sort and a per-row policy summary. The
  # controller maps ForbiddenError to 403.
  class ListAccounts
    # Raised when the requester may not list accounts (not an admin, or
    # the token's scope cannot read accounts). The controller maps this
    # to 403 -- unlike account detail, the index's existence is no secret.
    class ForbiddenError < StandardError
      def message
        'Only admins may list all accounts'
      end
    end

    def self.call(requester:, auth_scope:, role_filter: nil, sort: nil)
      policy = AccountPolicy.new(requester, auth_scope:)
      raise ForbiddenError unless policy.can_index_all?

      AccountPolicy::AdminScope.new(requester)
                               .viewable(role_filter:, sort:)
                               .map { |account| envelope_for(account, requester, auth_scope) }
    end

    def self.envelope_for(account, requester, auth_scope)
      envelope = JSON.parse(account.to_json)
      envelope['policies'] = AccountPolicy.new(requester, account, auth_scope:).index_summary
      envelope
    end
  end
end
