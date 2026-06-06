# frozen_string_literal: true

module Tyto
  # Authorization rules for system-role assignment. Delegates the actor
  # half ("can the viewer manage system roles at all?") to AccountPolicy
  # and layers per-target constraints on top.
  class SystemRolePolicy
    def initialize(viewer, target_account, auth_scope: AuthScope.new)
      @viewer = viewer
      @target_account = target_account
      @auth_scope = auth_scope
    end

    def can_manage?
      return false unless @viewer && @target_account
      return false unless AccountPolicy.new(@viewer, auth_scope: @auth_scope).can_manage_system_roles?

      target_constraints_pass?
    end

    def summary
      { can_manage: can_manage? }
    end

    private

    # Per-target invariants — e.g. an admin can't revoke their own admin role
    # (avoids the no-admin-left lockout). Today's policy is loose; richer
    # constraints can land here without touching call sites.
    def target_constraints_pass?
      true
    end
  end
end
