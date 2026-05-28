# frozen_string_literal: true

module Tyto
  # Creates a new event under a course
  class CreateEventForCourse
    class NotAuthorizedError < StandardError; end

    def self.call(current_account_id:, course_id:, event_data:)
      current_account = Account.first(id: current_account_id)
      course = Course.first(id: course_id)
      raise NotAuthorizedError, 'Only teaching staff can create events' unless
        CoursePolicy.new(current_account, course).can_edit?

      course.add_event(event_data)
    end
  end
end
