# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:events) do
      uuid :id, primary_key: true
      foreign_key :course_id, :courses, null: false
      foreign_key :location_id, :locations

      String   :name, null: false
      DateTime :start_at
      DateTime :end_at

      DateTime :created_at
      DateTime :updated_at

      unique %i[course_id name start_at]
    end
  end
end
