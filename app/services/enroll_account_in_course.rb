# frozen_string_literal: true

module Tyto
  # Enrolls an account in a course under a named role.
  # Single seam for non-owner enrollments; policy checks arrive in 7-policies.
  class EnrollAccountInCourse
    class UnknownRoleError < StandardError; end

    def self.call(account_id:, course_id:, role_name:)
      role = Role.first(name: role_name) or raise(UnknownRoleError, role_name)
      Enrollment.create(
        account_id:,
        course_id:,
        role_id: role.id
      )
    end
  end
end
