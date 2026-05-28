# frozen_string_literal: true

module Tyto
  # Authorization rules for an Event. CRUD is teaching staff only;
  # viewing requires enrollment in the parent course.
  class EventPolicy
    RESOURCE = 'events'

    def initialize(account, event, auth_scope: AuthScope.new)
      @account = account
      @event = event
      @auth_scope = auth_scope
    end

    def can_view?              = can_read? && course_policy.can_view?
    def can_edit?              = can_write? && course_policy.can_edit?
    def can_delete?            = can_write? && course_policy.can_edit?
    def can_record_attendance? = can_write? && course_policy.can_record_attendance? && @event&.live_now?

    def summary
      {
        can_view: can_view?,
        can_edit: can_edit?,
        can_delete: can_delete?,
        can_record_attendance: can_record_attendance?
      }
    end

    def index_summary
      {
        can_view: can_view?,
        can_edit: can_edit?,
        can_record_attendance: can_record_attendance?
      }
    end

    private

    def can_read?  = @auth_scope.can_read?(RESOURCE)
    def can_write? = @auth_scope.can_write?(RESOURCE)

    # The inner course policy carries no token scope (defaults to FULL), so it
    # answers a pure role question; EventPolicy applies the `events` scope gate.
    def course_policy
      @course_policy ||= CoursePolicy.new(@account, @event&.course)
    end
  end
end
