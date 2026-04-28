# frozen_string_literal: true

module Tyto
  # Enrolls an account in a course under a named role.
  # Single seam for non-owner enrollments; policy checks arrive in 7-policies.
  class EnrollAccountInCourse
    class UnknownRoleError < StandardError; end
    class NotAuthorizedError < StandardError; end

    # NOTE: role-checking belongs in a Policy object (see branch 7-policies).
    # It lives here for now to demonstrate the smell that motivates extracting it.
    # rubocop:disable Metrics/MethodLength
    def self.call(current_account_id:, target_account_id:, course_id:, role_name:)
      current_role = Enrollment
                     .where(account_id: current_account_id, course_id:).all
                     .map { |e| e.role&.name }
      unless current_role.intersect?(Role::TEACHING)
        raise NotAuthorizedError, 'Only teaching staff can manage enrollments'
      end

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
