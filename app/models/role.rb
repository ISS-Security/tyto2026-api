# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models a named role (system-level or per-course)
  class Role < Sequel::Model
    class UnknownRoleError < StandardError; end

    # Role-name groupings kept for back-compat with ad-hoc role checks
    # remaining outside Policy objects (one cleanup branch behind).
    TEACHING = %w[owner instructor staff].freeze
    COURSE_CREATORS = %w[creator admin].freeze
    SYSTEM = %w[admin creator member].freeze
    COURSE = %w[owner instructor staff student].freeze

    many_to_many :accounts, join_table: :accounts_roles
    one_to_many :enrollments

    plugin :timestamps, update_on_create: true

    def self.id_for(name)
      first(name:)&.id or raise UnknownRoleError, name
    end

    # System-role predicates
    def admin?   = name == 'admin'
    def creator? = name == 'creator'
    def member?  = name == 'member'

    # Course-role predicates
    def owner?      = name == 'owner'
    def instructor? = name == 'instructor'
    def staff?      = name == 'staff'
    def student?    = name == 'student'

    # Groupings — what Policy objects actually ask
    def teaching?       = TEACHING.include?(name)
    def course_creator? = COURSE_CREATORS.include?(name)
    def system?         = SYSTEM.include?(name)
    def course_role?    = COURSE.include?(name)

    def to_json(options = {})
      JSON({ id:, name: }, options)
    end
  end
end
