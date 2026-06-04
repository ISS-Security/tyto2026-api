# frozen_string_literal: true

require 'sequel'

module Tyto
  # Links a Tyto account to an external SSO identity, keyed on
  # (provider, external_id). Provider-agnostic by design: Google ships first
  # (`provider='google'`, `external_id =` the id_token `sub`); a second
  # provider needs only a new verifier + mapper + `provider` value.
  class SsoIdentity < Sequel::Model
    many_to_one :account

    plugin :whitelist_security
    set_allowed_columns :account_id, :provider, :external_id

    plugin :timestamps, update_on_create: true
  end
end
