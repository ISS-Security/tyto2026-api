# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:enrollments) do
      primary_key :id
      foreign_key :account_id, :accounts, null: false
      foreign_key :course_id, :courses, null: false
      foreign_key :role_id, :roles, null: false

      DateTime :created_at
      DateTime :updated_at

      unique %i[account_id course_id role_id]
    end
  end
end
