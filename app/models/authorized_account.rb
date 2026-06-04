# frozen_string_literal: true

require 'json'

require_relative '../lib/auth_scope'
require_relative '../lib/auth_token'

module Tyto
  # Pairs an account envelope with an AuthScope. Used two ways:
  #
  #   1. Minting (login / account-detail): wrap an account envelope + scope and
  #      hand out `to_h` (the account plus a freshly-minted, scoped auth token).
  #      Pass `account_id:` so the internal id rides inside the encrypted token
  #      only -- it stays out of the plaintext `account` envelope.
  #
  #   2. Reconstruction (HttpRequest): wrap the decrypted token payload (an
  #      envelope that already carries the id) plus the token's scope, exposing
  #      `.account` (a hash) and `.scope` for controllers and policies.
  class AuthorizedAccount
    attr_reader :account, :scope

    def initialize(account, auth_scope = AuthScope.new, account_id: nil)
      @account = account
      @account_id = account_id
      @scope =
        case auth_scope
        when AuthScope then auth_scope
        when nil then AuthScope.new
        else AuthScope.new(auth_scope)
        end
    end

    def token
      @token ||= AuthToken.new(token_payload, scope: @scope).to_s
    end

    def to_h
      {
        type: 'authorized_account',
        attributes: { account: @account, auth_token: token }
      }
    end

    def to_json(options = {})
      JSON(to_h, options)
    end

    private

    # The token only needs to *identify* the account (plus carry its scope);
    # the API re-derives roles/policies from the id on every request and never
    # reads anything else out of the decrypted token. So we tokenize a minimal
    # identity payload rather than the full display envelope -- this keeps the
    # auth token small. The rich envelope still rides in the plaintext `to_h`
    # response (`attributes.account`) for the App to render.
    def token_payload
      attrs = @account['attributes'] || {}
      {
        'type' => 'account',
        'attributes' => { 'id' => @account_id || attrs['id'], 'username' => attrs['username'] }
      }
    end
  end
end
