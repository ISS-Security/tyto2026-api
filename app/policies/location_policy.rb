# frozen_string_literal: true

module Tyto
  # Authorization rules for a Location. CRUD is teaching staff only;
  # viewing requires enrollment in the parent course.
  class LocationPolicy
    RESOURCE = 'locations'

    def initialize(account, location, auth_scope: AuthScope.new)
      @account = account
      @location = location
      @auth_scope = auth_scope
    end

    def can_view?   = can_read? && course_policy.can_view?
    def can_edit?   = can_write? && course_policy.can_edit?
    def can_delete? = can_write? && course_policy.can_edit?

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

    def can_read?  = @auth_scope.can_read?(RESOURCE)
    def can_write? = @auth_scope.can_write?(RESOURCE)

    def course_policy
      @course_policy ||= CoursePolicy.new(@account, @location&.course)
    end
  end
end
