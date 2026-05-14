# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models a scheduled course event (class session)
  class Event < Sequel::Model
    one_to_many :attendances
    many_to_one :course
    many_to_one :location

    plugin :uuid, field: :id
    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :name, :start_at, :end_at, :location_id

    def live_now?
      now = Time.now
      start_at && end_at && start_at <= now && now <= end_at
    end

    def self.live_now(now = Time.now)
      where { (start_at <= now) & (end_at >= now) }
    end

    def attendance_id_for(account_id)
      Attendance.first(account_id:, event_id: id)&.id
    end

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          type: 'event',
          attributes: {
            id:,
            name:,
            start_at:,
            end_at:
          },
          include: {
            course:,
            location:
          }
        }, options
      )
    end
    # rubocop:enable Metrics/MethodLength

    # Caller-scoped envelope: includes `my_attendance_id` so the App can
    # render "Attended" vs "Check in" without a second fetch.
    # rubocop:disable Metrics/MethodLength
    def as_hash_for(account_id)
      {
        type: 'event',
        attributes: {
          id:,
          name:,
          start_at:,
          end_at:,
          my_attendance_id: attendance_id_for(account_id)
        },
        include: {
          course:,
          location:
        }
      }
    end
    # rubocop:enable Metrics/MethodLength
  end
end
