# frozen_string_literal: true

module Tyto
  # Creates a new location under a course
  class CreateLocationForCourse
    def self.call(course_id:, location_data:)
      Course.first(id: course_id).add_location(location_data)
    end
  end
end
