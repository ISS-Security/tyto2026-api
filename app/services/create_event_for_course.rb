# frozen_string_literal: true

module Tyto
  # Creates a new event under a course
  class CreateEventForCourse
    def self.call(course_id:, event_data:)
      Course.first(id: course_id).add_event(event_data)
    end
  end
end
