# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_join_table(account_id: :accounts, role_id: :roles)
  end
end
