# frozen_string_literal: true

module Tyto
  # Cross-course list of events the caller can currently check in to:
  # caller is enrolled as student AND event window covers now AND
  # caller has not already checked in.
  class ListEligibleEvents
    # rubocop:disable Metrics/MethodLength
    def self.call(current_account_id:)
      student_role = Role.first(name: 'student')
      return [] unless student_role

      student_course_ids = Enrollment
                           .where(account_id: current_account_id, role_id: student_role.id)
                           .select_map(:course_id)
      return [] if student_course_ids.empty?

      already_attended_event_ids = Attendance
                                   .where(account_id: current_account_id)
                                   .select_map(:event_id)

      events = Event.live_now.where(course_id: student_course_ids)
      events = events.exclude(id: already_attended_event_ids) if already_attended_event_ids.any?
      events.all
    end
    # rubocop:enable Metrics/MethodLength
  end
end
