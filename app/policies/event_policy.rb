# frozen_string_literal: true

module Tyto
  # Authorization rules for an Event. CRUD is teaching staff only;
  # viewing requires enrollment in the parent course.
  class EventPolicy
    def initialize(account, event)
      @account = account
      @event = event
    end

    def can_view?              = course_policy.can_view?
    def can_edit?              = course_policy.can_edit?
    def can_delete?            = course_policy.can_edit?
    def can_record_attendance? = course_policy.can_record_attendance? && @event&.live_now?

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

    def course_policy
      @course_policy ||= CoursePolicy.new(@account, @event&.course)
    end
  end
end
