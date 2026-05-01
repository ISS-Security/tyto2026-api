# frozen_string_literal: true

require 'roda'
require_relative 'app'

module Tyto
  # Web controller for Tyto API
  class Api < Roda
    route('accounts') do |routing|
      @account_route = "#{@api_root}/accounts"

      routing.on String do |username|
        routing.on 'system_roles' do
          routing.on String do |role_name|
            # PUT api/v1/accounts/[username]/system_roles/[role_name]
            # Idempotent: 201 the first time, 200 on re-PUT.
            routing.put do
              body = HttpRequest.new(routing).body_data
              current_account_id = body[:current_account_id]
              routing.halt(401, { message: 'Missing current_account_id' }.to_json) unless current_account_id

              result = AssignSystemRole.call(
                current_account_id:, target_username: username, role_name:
              )

              response.status = result.created? ? 201 : 200
              { message: 'System role assigned', data: result.account }.to_json
            rescue Tyto::AssignSystemRole::NotAuthorizedError => e
              routing.halt 403, { message: e.message }.to_json
            rescue Tyto::AssignSystemRole::UnknownRoleError
              routing.halt 400, { message: 'Unknown system role' }.to_json
            rescue Tyto::AssignSystemRole::UnknownAccountError
              routing.halt 404, { message: 'Account not found' }.to_json
            rescue StandardError => e
              Api.logger.error "UNKNOWN ERROR: #{e.message}"
              routing.halt 500, { message: 'Unknown server error' }.to_json
            end

            # DELETE api/v1/accounts/[username]/system_roles/[role_name]
            routing.delete do
              body = HttpRequest.new(routing).body_data
              current_account_id = body[:current_account_id]
              routing.halt(401, { message: 'Missing current_account_id' }.to_json) unless current_account_id

              current_account = Account.first(id: current_account_id)
              unless current_account && current_account.system_roles.map(&:name).include?('admin')
                routing.halt 403, { message: 'Only admins can manage system roles' }.to_json
              end

              routing.halt(400, { message: 'Unknown system role' }.to_json) unless Role::SYSTEM.include?(role_name)
              role = Role.first(name: role_name)
              routing.halt(400, { message: 'Unknown system role' }.to_json) unless role

              target = Account.first(username:)
              routing.halt(404, { message: 'Account not found' }.to_json) unless target
              unless target.system_roles_dataset.where(name: role_name).any?
                routing.halt 404, { message: 'Role not assigned' }.to_json
              end

              target.remove_system_role(role)
              { message: 'System role revoked', data: target }.to_json
            rescue StandardError => e
              Api.logger.error "UNKNOWN ERROR: #{e.message}"
              routing.halt 500, { message: 'Unknown server error' }.to_json
            end
          end
        end

        # GET api/v1/accounts/[username]
        # Self-view, or admin viewing any account.
        routing.get do
          current_account_id = routing.params['current_account_id']
          routing.halt(401, { message: 'Missing current_account_id' }.to_json) unless current_account_id

          account = Account.first(username:)
          routing.halt(404, { message: 'Account not found' }.to_json) unless account

          requester = Account.first(id: current_account_id)
          is_self = requester && requester.id == account.id
          is_admin = requester && requester.system_roles.map(&:name).include?('admin')
          routing.halt(404, { message: 'Account not found' }.to_json) unless is_self || is_admin

          account.to_json
        rescue StandardError => e
          routing.halt 404, { message: e.message }.to_json
        end
      end

      # POST api/v1/accounts
      routing.post do
        new_data = HttpRequest.new(routing).body_data
        new_account = Account.new(new_data)
        raise('Could not save account') unless new_account.save_changes

        response.status = 201
        response['Location'] = "#{@account_route}/#{new_account.id}"
        { message: 'Account saved', data: new_account }.to_json
      rescue Sequel::MassAssignmentRestriction
        Api.logger.warn "MASS-ASSIGNMENT: #{new_data.keys}"
        routing.halt 400, { message: 'Illegal Attributes' }.to_json
      rescue StandardError => e
        Api.logger.error "UNKNOWN ERROR: #{e.message}"
        routing.halt 500, { message: 'Unknown server error' }.to_json
      end
    end
  end
end
