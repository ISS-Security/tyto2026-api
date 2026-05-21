# frozen_string_literal: true

module Tyto
  # Records that the calling account attended a specific event.
  # Inline student-role check; extracted into AttendancePolicy in 7-policies.
  class RecordAttendance
    class NotAuthorizedError < StandardError; end
    class UnknownEventError < StandardError; end
    class NotLiveError < StandardError; end

    # rubocop:disable Metrics/MethodLength
    def self.call(current_account_id:, course_id:, event_id:)
      event = Event.first(id: event_id, course_id:)
      raise UnknownEventError, 'Event not found' unless event

      caller_roles = Enrollment
                     .where(account_id: current_account_id, course_id:)
                     .map { |e| e.role&.name }
      raise NotAuthorizedError, 'Only enrolled students can check in' unless
        caller_roles.include?('student')

      raise NotLiveError, 'Event is not live right now' unless event.live_now?

      Attendance.create(
        account_id: current_account_id,
        course_id:,
        event_id: event.id,
        checked_in_at: Time.now
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
