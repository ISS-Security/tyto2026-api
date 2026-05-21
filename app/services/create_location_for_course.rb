# frozen_string_literal: true

module Tyto
  # Creates a new location under a course
  class CreateLocationForCourse
    class NotAuthorizedError < StandardError; end

    def self.call(current_account_id:, course_id:, location_data:)
      current_account = Account.first(id: current_account_id)
      course = Course.first(id: course_id)
      raise NotAuthorizedError, 'Only teaching staff can create locations' unless
        CoursePolicy.new(current_account, course).can_edit?

      course.add_location(location_data)
    end
  end
end
