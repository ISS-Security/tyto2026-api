# frozen_string_literal: true

module Tyto
  # Authorization rules for managing enrollments. Initialize with the
  # course for course-wide checks (create / list); initialize with an
  # Enrollment row for per-row checks (leave).
  class EnrollmentPolicy
    def initialize(account, target)
      @account = account
      @target = target
    end

    def can_manage?
      return false unless @account && course

      CoursePolicy.new(@account, course).can_enroll?
    end

    def can_leave?
      return false unless @account && enrollment_target

      enrollment_target.account_id == @account.id &&
        enrollment_target.role &&
        !enrollment_target.role.owner?
    end

    def summary
      {
        can_manage: can_manage?,
        can_leave: can_leave?
      }
    end

    def index_summary
      { can_manage: can_manage? }
    end

    private

    def course
      return @target if @target.is_a?(Course)

      @target.course if @target.respond_to?(:course) && @target.course
    end

    def enrollment_target
      @target if @target.is_a?(Enrollment)
    end
  end
end
