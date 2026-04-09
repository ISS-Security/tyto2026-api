# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models a location for a course
  class Location < Sequel::Model
    many_to_one :course
    one_to_many :events

    plugin :timestamps

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'location',
            attributes: {
              id:,
              name:,
              longitude:,
              latitude:
            }
          },
          included: {
            course:
          }
        }, options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
