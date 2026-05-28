# frozen_string_literal: true

module Tyto
  class AttendancePolicy
    # Per-event attendance listing — teaching staff see every attendance for
    # the event; students see only their own.
    class EventScope
      def initialize(account, event)
        @account = account
        @event = event
      end

      def viewable
        return [] unless @account && @event

        course = @event.course
        return [] unless course

        if CoursePolicy.new(@account, course).can_edit?
          Attendance.where(event_id: @event.id).all
        else
          Attendance.where(event_id: @event.id, account_id: @account.id).all
        end
      end
    end

    # Cross-course list of events the account can currently check in to:
    # account is enrolled as a student, event is live now, and they have not
    # already checked in. Replaces the old ListEligibleEvents service.
    class EligibleScope
      def initialize(account)
        @account = account
      end

      # rubocop:disable Metrics/MethodLength
      def events
        return [] unless @account

        student_role = Role.first(name: 'student')
        return [] unless student_role

        student_course_ids = Enrollment
                             .where(account_id: @account.id, role_id: student_role.id)
                             .select_map(:course_id)
        return [] if student_course_ids.empty?

        already_attended_event_ids = Attendance
                                     .where(account_id: @account.id)
                                     .select_map(:event_id)

        events = Event.live_now.where(course_id: student_course_ids)
        events = events.exclude(id: already_attended_event_ids) if already_attended_event_ids.any?
        events.all
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
