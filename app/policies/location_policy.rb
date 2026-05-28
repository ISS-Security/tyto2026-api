# frozen_string_literal: true

module Tyto
  # Authorization rules for a Location. CRUD is teaching staff only;
  # viewing requires enrollment in the parent course.
  class LocationPolicy
    def initialize(account, location)
      @account = account
      @location = location
    end

    def can_view?   = course_policy.can_view?
    def can_edit?   = course_policy.can_edit?
    def can_delete? = course_policy.can_edit?

    def summary
      {
        can_view: can_view?,
        can_edit: can_edit?,
        can_delete: can_delete?
      }
    end

    def index_summary
      { can_view: can_view?, can_edit: can_edit? }
    end

    private

    def course_policy
      @course_policy ||= CoursePolicy.new(@account, @location&.course)
    end
  end
end
