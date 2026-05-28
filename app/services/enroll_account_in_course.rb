# frozen_string_literal: true

module Tyto
  # Enrolls an account in a course under a named role.
  # Authorization sits behind EnrollmentPolicy.
  class EnrollAccountInCourse
    class UnknownRoleError < StandardError; end
    class UnknownCourseError < StandardError; end
    class UnknownCurrentAccountError < StandardError; end
    class NotAuthorizedError < StandardError; end

    # rubocop:disable Metrics/MethodLength
    def self.call(current_account_id:, target_account_id:, course_id:, role_name:, auth_scope: AuthScope.new)
      current_account = Account.first(id: current_account_id) or raise UnknownCurrentAccountError
      course = Course.first(id: course_id) or raise UnknownCourseError

      unless EnrollmentPolicy.new(current_account, course, auth_scope:).can_manage?
        raise NotAuthorizedError, 'Only teaching staff can manage enrollments'
      end

      raise UnknownRoleError, role_name unless Role::COURSE.include?(role_name)

      role = Role.first(name: role_name) or raise(UnknownRoleError, role_name)
      Enrollment.create(
        account_id: target_account_id,
        course_id:,
        role_id: role.id
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
