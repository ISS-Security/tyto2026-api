# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../policies/policy_helper'

# End-to-end proof that a READ_ONLY ("API key") token reads but cannot mutate,
# while a FULL session token retains role-based write access.
describe 'AuthScope enforcement at the API boundary' do
  include Rack::Test::Methods
  include PolicyWorld

  before { setup_policy_world }

  def read_only_header(account)
    auth_header_with_scope(account, Tyto::AuthScope::READ_ONLY)
  end

  describe 'READ_ONLY token' do
    it 'HAPPY: can read the courses index' do
      get '/api/v1/courses', nil, read_only_header(@creator)
      _(last_response.status).must_equal 200
    end

    it 'HAPPY: can read a course detail, but its policy summary forbids edit' do
      get "/api/v1/courses/#{@course.id}", nil, read_only_header(@creator)
      _(last_response.status).must_equal 200

      policies = JSON.parse(last_response.body)['policies']
      _(policies['can_view']).must_equal true
      _(policies['can_edit']).must_equal false
    end

    it 'BAD: cannot create a course (write denied by scope)' do
      post '/api/v1/courses', { name: 'Blocked', description: 'x' }.to_json,
           read_only_header(@creator).merge('CONTENT_TYPE' => 'application/json')
      _(last_response.status).must_equal 403
    end

    it 'BAD: cannot create an event (write denied by scope)' do
      post "/api/v1/courses/#{@course.id}/events",
           { name: 'E', start_at: Time.now, end_at: Time.now + 60, location_id: @location.id }.to_json,
           read_only_header(@instructor).merge('CONTENT_TYPE' => 'application/json')
      _(last_response.status).must_equal 403
    end
  end

  describe 'FULL token (control)' do
    it 'HAPPY: can create a course' do
      post '/api/v1/courses', { name: 'OK', description: 'x' }.to_json,
           auth_request_header(@creator)
      _(last_response.status).must_equal 201
    end
  end
end
