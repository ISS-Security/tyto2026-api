# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Records that an account checked in to an event of a course.
  class Attendance < Sequel::Model
    many_to_one :account
    many_to_one :event
    many_to_one :course

    plugin :whitelist_security
    set_allowed_columns :account_id, :event_id, :course_id, :checked_in_at

    plugin :timestamps, update_on_create: true

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          type: 'attendance',
          attributes: {
            id:,
            account_id:,
            event_id:,
            course_id:,
            checked_in_at:
          }
        }, options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
