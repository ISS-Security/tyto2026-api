# frozen_string_literal: true

module Tyto
  # Authorization rules for a single Course.
  # Entity-scoped: every predicate answers "can this account do X to *this* course?"
  # Actor-scoped predicates (e.g. can_create_course?) live on AccountPolicy.
  class CoursePolicy
    RESOURCE = 'courses'

    def initialize(account, course, auth_scope: AuthScope.new)
      @account = account
      @course = course
      @auth_scope = auth_scope
    end

    def can_view?               = can_read? && (account_is_enrolled? || account_is_admin?)
    def can_edit?               = can_write? && (account_is_teaching_staff? || account_is_admin?)
    def can_delete?             = can_write? && (account_is_owner? || account_is_admin?)
    def can_enroll?             = can_write? && (account_is_teaching_staff? || account_is_admin?)
    def can_record_attendance?  = can_write? && account_is_student?

    def summary
      {
        can_view: can_view?,
        can_edit: can_edit?,
        can_delete: can_delete?,
        can_enroll: can_enroll?,
        can_record_attendance: can_record_attendance?
      }
    end

    def index_summary
      { can_view: can_view?, can_edit: can_edit? }
    end

    private

    def can_read?  = @auth_scope.can_read?(RESOURCE)
    def can_write? = @auth_scope.can_write?(RESOURCE)

    def account_is_enrolled?
      return false unless @account && @course

      Enrollment.where(account_id: @account.id, course_id: @course.id).any?
    end

    def account_is_owner?
      enrollment_roles.any?(&:owner?)
    end

    def account_is_teaching_staff?
      enrollment_roles.any?(&:teaching?)
    end

    def account_is_student?
      enrollment_roles.any?(&:student?)
    end

    def account_is_admin?
      @account&.admin? || false
    end

    def enrollment_roles
      return [] unless @account && @course

      @enrollment_roles ||= Enrollment
                            .where(account_id: @account.id, course_id: @course.id)
                            .filter_map(&:role)
    end
  end
end
