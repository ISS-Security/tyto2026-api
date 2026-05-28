# frozen_string_literal: true

module Tyto
  # Find account, check password, and issue an encrypted auth token.
  class AuthenticateAccount
    # Raised when credentials don't match a known account.
    class UnauthorizedError < StandardError
      def initialize(credentials)
        @credentials = credentials
        super
      end

      def message
        "Invalid credentials for: #{@credentials[:username]}"
      end
    end

    def self.call(credentials)
      account = Account.first(username: credentials[:username])
      raise UnauthorizedError, credentials unless
        account&.password?(credentials[:password])

      account_envelope = JSON.parse(account.to_json)
      # Authentication implies self-view, so the response carries the
      # actor-scoped capabilities the App reads via `current_account.admin?`
      # etc. Without this the App's session has no `capabilities` key and
      # every actor-scoped predicate silently returns false.
      account_envelope['capabilities'] = AccountPolicy.new(account).capabilities
      { type: 'authenticated_account',
        attributes: { account: account_envelope, auth_token: token_for(account_envelope, account.id) } }
    end

    # Encrypted token carries only a minimal identity payload (the internal
    # `id` the API needs for inline role checks, plus the username). The API
    # re-derives roles/policies from the id on each request, so the token does
    # not need the full envelope -- keeping it small. The id stays out of the
    # plaintext response; only callers with MSG_KEY can read it back. Login
    # issues a FULL-scope session token (write implies read); the account-detail
    # endpoint mints a reduced READ_ONLY token for sharing.
    def self.token_for(envelope, account_id)
      username = envelope.dig('attributes', 'username')
      token_payload = {
        'type' => 'account',
        'attributes' => { 'id' => account_id, 'username' => username }
      }
      AuthToken.new(token_payload, scope: AuthScope.new).to_s
    end
  end
end
