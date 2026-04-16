# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models a scheduled course event (class session)
  class Event < Sequel::Model
    many_to_one :course
    many_to_one :location

    plugin :uuid, field: :id
    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :name, :start_at, :end_at, :location_id

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'event',
            attributes: {
              id:,
              name:,
              start_at:,
              end_at:
            }
          },
          included: {
            course:,
            location:
          }
        }, options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
