# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:attendances) do
      primary_key :id
      foreign_key :account_id, :accounts, null: false
      foreign_key :event_id, :events, type: :uuid, null: false
      foreign_key :course_id, :courses, null: false

      DateTime :checked_in_at, null: false

      DateTime :created_at
      DateTime :updated_at

      unique %i[account_id event_id]
    end
  end
end
