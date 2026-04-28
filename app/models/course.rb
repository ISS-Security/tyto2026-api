# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models a course
  class Course < Sequel::Model
    one_to_many :events
    one_to_many :locations
    one_to_many :enrollments
    # :destroy instantiates each row so Sequel hooks and nested dependencies fire.
    # :delete bulk-removes enrollments without instantiating each row.
    plugin :association_dependencies,
           events: :destroy,
           locations: :destroy,
           enrollments: :delete

    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :name, :description

    def owner
      accounts_in_role('owner').first
    end

    def instructors = accounts_in_role('instructor')
    def staff       = accounts_in_role('staff')
    def students    = accounts_in_role('student')

    def to_json(options = {})
      JSON(
        {
          type: 'course',
          attributes: {
            id:,
            name:,
            description:
          }
        }, options
      )
    end

    private

    def accounts_in_role(role_name)
      role = Role.first(name: role_name)
      return [] unless role

      enrollments_dataset.where(role_id: role.id).map(&:account)
    end
  end
end
