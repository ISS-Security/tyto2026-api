# frozen_string_literal: true

module Tyto
  class AccountPolicy
    # Filters accounts to those the viewer can list. Admins see everyone;
    # non-admins see only themselves.
    class AdminScope
      def initialize(viewer)
        @viewer = viewer
      end

      def viewable
        return [] unless @viewer
        return Account.all if @viewer.admin?

        [@viewer]
      end
    end
  end
end
