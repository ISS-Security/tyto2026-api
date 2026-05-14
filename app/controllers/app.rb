# frozen_string_literal: true

require 'roda'
require 'json'

require_relative 'http_request'

module Tyto
  # Web controller for Tyto API
  class Api < Roda
    plugin :halt
    plugin :all_verbs
    plugin :multi_route
    plugin :request_headers

    route do |routing|
      response['Content-Type'] = 'application/json'

      http_request = HttpRequest.new(routing)
      http_request.secure? ||
        routing.halt(403, { message: 'TLS/SSL Required' }.to_json)

      begin
        @auth_account = http_request.authenticated_account
      rescue AuthToken::InvalidTokenError
        routing.halt 403, { message: 'Invalid auth token' }.to_json
      rescue AuthToken::ExpiredTokenError
        routing.halt 403, { message: 'Expired auth token' }.to_json
      end

      routing.root do
        { message: 'TytoAPI up at /api/v1' }.to_json
      end

      routing.on 'api' do
        routing.on 'v1' do
          @api_root = 'api/v1'
          routing.multi_route
        end
      end
    end
  end
end
