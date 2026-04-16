# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models a scheduled course event (class session)
  class Event < Sequel::Model
    unrestrict_primary_key
    many_to_one :course
    many_to_one :location

    plugin :timestamps

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
