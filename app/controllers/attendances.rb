# frozen_string_literal: true

require 'roda'
require_relative 'app'

module Tyto
  # Top-level attendance controller for cross-course lookups.
  class Api < Roda
    route('attendances') do |routing|
      current_account_id = @auth_account&.dig('attributes', 'id')
      routing.halt(401, { message: 'Authentication required' }.to_json) unless current_account_id

      # GET api/v1/attendances/eligible
      # Returns events the caller can currently check in to (live now,
      # caller is a student in the course, no existing attendance row).
      routing.is 'eligible' do
        routing.get do
          events = ListEligibleEvents.call(current_account_id:)
          payload = events.map { |e| e.as_hash_for(current_account_id) }
          { data: payload }.to_json
        rescue StandardError => e
          Api.logger.error "UNKNOWN ERROR: #{e.message}"
          routing.halt 500, { message: 'Unknown server error' }.to_json
        end
      end
    end
  end
end
