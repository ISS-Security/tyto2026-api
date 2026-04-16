# frozen_string_literal: true

require 'sequel'

Sequel.migration do
  change do
    create_table(:locations) do
      primary_key :id
      foreign_key :course_id, :courses

      String :name, null: false
      Float  :longitude
      Float  :latitude

      DateTime :created_at
      DateTime :updated_at

      unique %i[course_id name]
    end
  end
end
