# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models a location for a course
  class Location < Sequel::Model
    many_to_one :course
    one_to_many :events

    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :name, :longitude, :latitude

    # Secure getters and setters
    def longitude
      SecureDB.decrypt(longitude_secure)
    end

    def longitude=(plaintext)
      self.longitude_secure = SecureDB.encrypt(plaintext)
    end

    def latitude
      SecureDB.decrypt(latitude_secure)
    end

    def latitude=(plaintext)
      self.latitude_secure = SecureDB.encrypt(plaintext)
    end

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
