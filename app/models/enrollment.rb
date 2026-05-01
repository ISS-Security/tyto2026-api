# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models an account's role in a specific course
  class Enrollment < Sequel::Model
    many_to_one :account
    many_to_one :course
    many_to_one :role

    plugin :whitelist_security
    set_allowed_columns :account_id, :course_id, :role_id

    plugin :timestamps, update_on_create: true

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          type: 'enrollment',
          attributes: {
            id:,
            account_id:,
            course_id:,
            role: role.name
          },
          include: {
            account: { username: account.username }
          }
        }, options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
