# frozen_string_literal: true

require 'roda'
require_relative 'app'

module Tyto
  # Web controller for Tyto API
  class Api < Roda
    route('accounts') do |routing|
      @account_route = "#{@api_root}/accounts"

      routing.on String do |username|
        # GET api/v1/accounts/[username]
        # Only the account holder themselves can fetch this profile.
        routing.get do
          current_account_id = routing.params['current_account_id']
          routing.halt(401, { message: 'Missing current_account_id' }.to_json) unless current_account_id

          account = Account.first(username:)
          unless account && account.id.to_s == current_account_id.to_s
            routing.halt 404, { message: 'Account not found' }.to_json
          end

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
