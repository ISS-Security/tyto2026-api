# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models a course
  class Course < Sequel::Model
    one_to_many :events
    one_to_many :locations
    plugin :association_dependencies,
           events: :destroy,
           locations: :destroy

    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :name, :description

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'course',
            attributes: {
              id:,
              name:,
              description:
            }
          }
        }, options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
