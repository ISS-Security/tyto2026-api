# frozen_string_literal: true

module Tyto
  class EventPolicy
    # Filters events to those the account can see — composes with
    # CoursePolicy::AccountScope so course-visibility rules stay single-sourced.
    class CourseScope
      def initialize(account, course)
        @account = account
        @course = course
      end

      def viewable
        return [] unless @account && @course
        return [] unless CoursePolicy.new(@account, @course).can_view?

        Event.where(course_id: @course.id).all
      end
    end
  end
end
