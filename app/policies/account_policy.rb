# frozen_string_literal: true

module Tyto
  # The one policy with two surfaces:
  #   - #summary: entity-scoped predicates about *this* account (viewer ↔ target)
  #   - #capabilities: actor-scoped predicates about the viewer in general
  #
  # Actor-scoped predicates (is_admin?, can_create_course?, can_manage_system_roles?)
  # are the rule-owners — other policies delegate to them rather than re-deriving
  # from system_roles. Resource policies stay uniformly resource-bound.
  class AccountPolicy
    RESOURCE = 'accounts'

    def initialize(viewer, target = viewer, auth_scope: AuthScope.new)
      @viewer = viewer
      @target = target
      @auth_scope = auth_scope
    end

    # --- Actor-scoped predicates (about @viewer, independent of @target) ---

    def is_admin? # rubocop:disable Naming/PredicatePrefix
      @viewer&.admin? || false
    end

    def can_create_course?
      @viewer&.course_creator? || false
    end

    def can_manage_system_roles?
      can_write? && is_admin?
    end

    # --- Entity-scoped predicates (about @viewer's permissions toward @target) ---

    def can_view?   = can_read? && (viewer_is_self? || is_admin?)
    def can_edit?   = can_write? && (viewer_is_self? || is_admin?)
    def can_delete? = can_write? && is_admin? && !viewer_is_self?

    def can_assign_role? = can_write? && is_admin?
    def can_revoke_role? = can_write? && is_admin?

    # Collection-scoped: may @viewer list *all* accounts? Admin-only (the
    # accounts index 403s everyone else), and a read per the scope ∧ role
    # convention -- a READ_ONLY key minted for an admin can list, never mutate.
    def can_index_all? = can_read? && is_admin?

    def summary
      {
        can_view: can_view?,
        can_edit: can_edit?,
        can_delete: can_delete?,
        can_assign_role: can_assign_role?,
        can_revoke_role: can_revoke_role?
      }
    end

    def index_summary
      {
        can_view: can_view?,
        can_edit: can_edit?,
        can_assign_role: can_assign_role?
      }
    end

    def capabilities
      {
        is_admin: is_admin?,
        can_create_course: can_create_course?,
        can_manage_system_roles: can_manage_system_roles?
      }
    end

    private

    def can_read?  = @auth_scope.can_read?(RESOURCE)
    def can_write? = @auth_scope.can_write?(RESOURCE)

    def viewer_is_self?
      @viewer && @target && @viewer.id == @target.id
    end
  end
end
