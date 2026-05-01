# frozen_string_literal: true

require 'roda'
require 'json'
require 'logger'

require_relative 'http_request'

module Tyto
  # Web controller for Tyto API
  class Api < Roda
    plugin :halt
    plugin :all_verbs
    plugin :multi_route

    route do |routing|
      response['Content-Type'] = 'application/json'

      HttpRequest.new(routing).secure? ||
        routing.halt(403, { message: 'TLS/SSL Required' }.to_json)

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
