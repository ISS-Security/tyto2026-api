# frozen_string_literal: true

module Tyto
  # Assigns a system role to an account. Idempotent: re-assigning a role
  # the account already has is a no-op success.
  class AssignSystemRole
    class UnknownRoleError < StandardError; end
    class UnknownAccountError < StandardError; end
    class NotAuthorizedError < StandardError; end

    Result = Struct.new(:account, :created, keyword_init: true) do
      alias_method :created?, :created
    end

    # NOTE: role-checking belongs in a Policy object (see branch 7-policies).
    # It lives here for now to demonstrate the smell that motivates extracting it.
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    def self.call(current_account_id:, target_username:, role_name:)
      current_account = Account.first(id: current_account_id) or raise UnknownAccountError
      unless current_account.system_roles.map(&:name).include?('admin')
        raise NotAuthorizedError, 'Only admins can manage system roles'
      end

      raise UnknownRoleError, role_name unless Role::SYSTEM.include?(role_name)

      role = Role.first(name: role_name) or raise(UnknownRoleError, role_name)
      target = Account.first(username: target_username) or raise UnknownAccountError
      already_assigned = target.system_roles_dataset.where(name: role_name).any?
      target.add_system_role(role) unless already_assigned

      Result.new(account: target, created: !already_assigned)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity
  end
end
