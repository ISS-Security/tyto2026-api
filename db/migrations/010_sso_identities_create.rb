# frozen_string_literal: true

require 'sequel'

# Additive migration (post-`5-deployable`, per Decision #10). An SSO identity is
# keyed on (provider, external_id) -- NOT email -- so one account can link
# several providers and a later email change never breaks the linkage. Google
# ships first; another provider needs only a new verifier + mapper, no schema
# change.
Sequel.migration do
  change do
    create_table(:sso_identities) do
      primary_key :id
      foreign_key :account_id, :accounts, null: false

      String :provider, null: false
      String :external_id, null: false

      DateTime :created_at
      DateTime :updated_at

      unique %i[provider external_id]    # the identity key
      unique %i[account_id provider]     # one identity per provider per account
    end
  end
end
