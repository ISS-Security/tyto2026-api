# frozen_string_literal: true

module Tyto
  class CoursePolicy
    # Filters courses to those the account can list.
    # Re-expresses CoursePolicy#can_view? as a SQL filter — kept in sync
    # via scope ↔ policy consistency cross-checks in the spec suite.
    class AccountScope
      def initialize(account)
        @account = account
      end

      def viewable
        return [] unless @account

        return Course.all if @account.admin?

        enrolled_course_ids = Enrollment
                              .where(account_id: @account.id)
                              .select_map(:course_id).uniq
        return [] if enrolled_course_ids.empty?

        Course.where(id: enrolled_course_ids).all
      end
    end
  end
end
