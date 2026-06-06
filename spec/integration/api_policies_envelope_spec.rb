# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../policies/policy_helper'

describe 'Policies envelope on read responses' do
  include Rack::Test::Methods
  include PolicyWorld

  before { setup_policy_world }

  # The account-detail endpoint now wraps the account envelope in an
  # AuthorizedAccount: { data: { attributes: { account: <envelope>, auth_token } } }.
  def account_envelope
    JSON.parse(last_response.body)['data']['attributes']['account']
  end

  describe 'self-Account envelope' do
    it 'HAPPY: carries both policies and capabilities' do
      get "/api/v1/accounts/#{@admin.username}", nil, auth_header(@admin)
      _(last_response.status).must_equal 200

      account = account_envelope
      _(account['policies']).wont_be_nil
      _(account['capabilities']).wont_be_nil
      _(account['capabilities']['is_admin']).must_equal true
      _(account['capabilities']['can_create_course']).must_equal true
    end

    it 'HAPPY: non-admin self envelope carries capabilities matching role' do
      get "/api/v1/accounts/#{@creator.username}", nil, auth_header(@creator)
      account = account_envelope
      _(account['capabilities']['is_admin']).must_equal false
      _(account['capabilities']['can_create_course']).must_equal true
    end
  end

  describe 'other-Account envelope' do
    it 'HAPPY: admin viewing other gets policies, no capabilities about target' do
      get "/api/v1/accounts/#{@creator.username}", nil, auth_header(@admin)
      _(last_response.status).must_equal 200

      account = account_envelope
      _(account['policies']).wont_be_nil
      _(account['capabilities']).must_be_nil # only on self envelope
    end
  end

  describe 'Course envelope' do
    it 'HAPPY: detail response carries full policies summary' do
      get "/api/v1/courses/#{@course.id}", nil, auth_header(@creator)
      _(last_response.status).must_equal 200

      result = JSON.parse(last_response.body)
      _(result['policies']).wont_be_nil
      _(result['policies']['can_edit']).must_equal true
      _(result['policies']['can_delete']).must_equal true
      _(result['policies']['can_record_attendance']).must_equal false
    end

    it 'HAPPY: index response carries slim index_summary on each row' do
      get '/api/v1/courses', nil, auth_header(@creator)
      result = JSON.parse(last_response.body)
      row = result['data'].first
      _(row['policies']).wont_be_nil
      _(row['policies'].keys.sort).must_equal %w[can_edit can_view]
    end

    it 'HAPPY: student sees can_record_attendance true' do
      get "/api/v1/courses/#{@course.id}", nil, auth_header(@student)
      result = JSON.parse(last_response.body)
      _(result['policies']['can_record_attendance']).must_equal true
      _(result['policies']['can_edit']).must_equal false
    end

    it 'SECURITY: outsider gets 404 (was: inline Enrollment check, now CoursePolicy)' do
      get "/api/v1/courses/#{@course.id}", nil, auth_header(@outsider)
      _(last_response.status).must_equal 404
    end
  end

  describe 'Event envelope' do
    it 'HAPPY: detail response carries policies with can_record_attendance' do
      get "/api/v1/courses/#{@course.id}/events/#{@live_event.id}",
        nil, auth_header(@student)
      _(last_response.status).must_equal 200
      result = JSON.parse(last_response.body)
      _(result[:policies] || result['policies']).wont_be_nil
    end
  end
end
