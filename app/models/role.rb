# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models a named role (system-level or per-course)
  class Role < Sequel::Model
    class UnknownRoleError < StandardError; end

    # Role-name groupings used by services for ad-hoc role checks.
    # Will be replaced by instance predicates (e.g. role.teaching?) when
    # role logic moves into Policy objects in 7-policies.
    TEACHING = %w[owner instructor staff].freeze
    COURSE_CREATORS = %w[creator admin].freeze

    many_to_many :accounts, join_table: :accounts_roles
    one_to_many :enrollments

    plugin :timestamps, update_on_create: true

    def self.id_for(name)
      first(name:)&.id or raise UnknownRoleError, name
    end

    def to_json(options = {})
      JSON({ id:, name: }, options)
    end
  end
end
