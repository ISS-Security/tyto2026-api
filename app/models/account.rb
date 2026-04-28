# frozen_string_literal: true

require 'sequel'
require 'json'
require_relative 'password'

module Tyto
  # Models a registered account
  class Account < Sequel::Model
    one_to_many :enrollments
    many_to_many :system_roles,
                 class: :'Tyto::Role',
                 join_table: :accounts_roles,
                 left_key: :account_id,
                 right_key: :role_id
    many_to_many :courses, join_table: :enrollments

    # :nullify on a many_to_many removes the join-table rows (not the
    # associated courses) — one bulk DELETE, keeps courses intact.
    plugin :association_dependencies, courses: :nullify

    plugin :whitelist_security
    set_allowed_columns :username, :email, :password, :avatar

    plugin :timestamps, update_on_create: true

    # Email is PII: store encrypted ciphertext + HMAC lookup hash.
    def email
      SecureDB.decrypt(email_secure)
    end

    def email=(plaintext)
      self.email_secure = SecureDB.encrypt(plaintext)
      self.email_hash   = SecureDB.hash(plaintext)
    end

    def password=(new_password)
      self.password_digest = Password.digest(new_password).to_s
    end

    def password?(try_password)
      digest = Password.from_digest(password_digest)
      digest.correct?(try_password)
    end

    def owned_courses
      owner_role = Role.first(name: 'owner')
      enrollments_dataset.where(role_id: owner_role.id).map(&:course)
    end

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          type: 'account',
          attributes: {
            id:,
            username:,
            email:
          },
          include: {
            enrollments: enrollments.map do |e|
              { course_id: e.course_id, course_name: e.course.name, role: e.role.name }
            end
          }
        }, options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
