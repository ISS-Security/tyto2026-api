# frozen_string_literal: true

module Tyto
  class AccountPolicy
    # Filters accounts to those the viewer can list. Admins see everyone;
    # non-admins see only themselves.
    class AdminScope
      # Reserved filter token (cross-repo contract with the App's Members
      # page): never a role name -- selects accounts with zero system roles.
      NONE_FILTER = 'none'

      # An account's "primary" system role for sorting: highest-precedence
      # role held; role-less accounts bucket last.
      ROLE_PRECEDENCE = %w[admin creator member].freeze

      def initialize(viewer)
        @viewer = viewer
      end

      def viewable(role_filter: nil, sort: nil)
        sort_accounts(filter_by_role(base_viewable, role_filter), sort)
      end

      private

      def base_viewable
        return [] unless @viewer
        return Account.all if @viewer.admin?

        [@viewer]
      end

      def filter_by_role(accounts, role_filter)
        return accounts unless role_filter
        return accounts.select { |a| a.system_roles.empty? } if role_filter == NONE_FILTER

        accounts.select { |a| a.system_roles.any? { |role| role.name == role_filter } }
      end

      def sort_accounts(accounts, sort)
        case sort
        when 'username' then accounts.sort_by(&:username)
        when 'role' then accounts.sort_by { |a| [primary_role_rank(a), a.username] }
        else accounts
        end
      end

      def primary_role_rank(account)
        role_names = account.system_roles.map(&:name)
        ROLE_PRECEDENCE.index { |name| role_names.include?(name) } || ROLE_PRECEDENCE.size
      end
    end
  end
end
