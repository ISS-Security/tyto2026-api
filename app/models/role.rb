# frozen_string_literal: true

require 'json'
require 'sequel'

module Tyto
  # Models a named role (system-level or per-course)
  class Role < Sequel::Model
    many_to_many :accounts, join_table: :accounts_roles
    one_to_many :enrollments

    plugin :timestamps, update_on_create: true

    def to_json(options = {})
      JSON({ id:, name: }, options)
    end
  end
end
