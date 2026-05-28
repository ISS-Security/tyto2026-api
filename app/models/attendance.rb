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
    set_allowed_columns :account_id, :event_id, :course_id, :checked_in_at,
                        :longitude, :latitude

    plugin :timestamps, update_on_create: true

    # Submitted check-in coordinates are PII: stored encrypted at rest and
    # never serialized back to clients. Nil-safe -- staff-recorded rows carry
    # no coordinates.
    def longitude
      longitude_secure && SecureDB.decrypt(longitude_secure)
    end

    def longitude=(plaintext)
      self.longitude_secure = plaintext && SecureDB.encrypt(plaintext.to_s)
    end

    def latitude
      latitude_secure && SecureDB.decrypt(latitude_secure)
    end

    def latitude=(plaintext)
      self.latitude_secure = plaintext && SecureDB.encrypt(plaintext.to_s)
    end

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
          },
          include: {
            account: { type: 'account', attributes: { username: account.username } }
          }
        }, options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
