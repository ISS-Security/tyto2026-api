# frozen_string_literal: true

module Tyto
  # Authorization rules for an Attendance record (and the act of recording one).
  # Initialize with an Event for can_record? checks; with an Attendance row for
  # can_view? / can_manage? checks.
  class AttendancePolicy
    RESOURCE = 'attendances'

    def initialize(account, target, auth_scope: AuthScope.new)
      @account = account
      @target = target
      @auth_scope = auth_scope
    end

    def can_record?
      return false unless can_write? && event_target && course

      CoursePolicy.new(@account, course).can_record_attendance? && event_target.live_now?
    end

    def can_view?
      return false unless can_read? && course

      account_is_self_owner? || account_is_teaching_staff_in_course?
    end

    def can_manage?
      return false unless can_write? && course

      account_is_teaching_staff_in_course?
    end

    def summary
      {
        can_view: can_view?,
        can_record: can_record?,
        can_manage: can_manage?
      }
    end

    def index_summary
      { can_view: can_view? }
    end

    private

    def can_read?  = @auth_scope.can_read?(RESOURCE)
    def can_write? = @auth_scope.can_write?(RESOURCE)

    def event_target
      return @target if @target.is_a?(Event)

      @target.event if @target.respond_to?(:event) && @target.event
    end

    def course
      return @target.course if @target.respond_to?(:course) && @target.course

      event_target&.course
    end

    def account_is_self_owner?
      return false unless @account && @target.respond_to?(:account_id)

      @target.account_id == @account.id
    end

    def account_is_teaching_staff_in_course?
      CoursePolicy.new(@account, course).can_edit?
    end
  end
end
