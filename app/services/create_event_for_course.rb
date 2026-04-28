# frozen_string_literal: true

module Tyto
  # Creates a new event under a course
  class CreateEventForCourse
    class NotAuthorizedError < StandardError; end

    # NOTE: role-checking belongs in a Policy object (see branch 7-policies).
    # It lives here for now to demonstrate the smell that motivates extracting it.
    def self.call(current_account_id:, course_id:, event_data:)
      current_role = Enrollment
                     .where(account_id: current_account_id, course_id:).all
                     .map { |e| e.role&.name }
      raise NotAuthorizedError, 'Only teaching staff can create events' unless
        current_role.intersect?(Role::TEACHING)

      Course.first(id: course_id).add_event(event_data)
    end
  end
end
