# frozen_string_literal: true

module Tyto
  # Records that the calling account attended a specific event.
  # Authorization sits behind AttendancePolicy.
  class RecordAttendance
    class NotAuthorizedError < StandardError; end
    class UnknownEventError < StandardError; end
    class UnknownCurrentAccountError < StandardError; end
    class NotLiveError < StandardError; end

    # rubocop:disable Metrics/MethodLength
    def self.call(current_account_id:, course_id:, event_id:)
      current_account = Account.first(id: current_account_id) or raise UnknownCurrentAccountError
      event = Event.first(id: event_id, course_id:)
      raise UnknownEventError, 'Event not found' unless event

      policy = AttendancePolicy.new(current_account, event)
      raise NotAuthorizedError, 'Only enrolled students can check in' unless
        CoursePolicy.new(current_account, event.course).can_record_attendance?

      raise NotLiveError, 'Event is not live right now' unless policy.can_record?

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
