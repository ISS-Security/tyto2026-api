# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Location Handling' do
  include Rack::Test::Methods

  before do
    wipe_database

    %w[admin creator member owner instructor staff student].each do |role_name|
      Tyto::Role.find_or_create(name: role_name)
    end

    @owner = Tyto::Account.create(DATA[:accounts][0])
    @owner.add_system_role(Tyto::Role.first(name: 'creator'))
    DATA[:courses].each do |course_data|
      Tyto::CreateCourseForOwner.call(
        current_account_id: @owner.id, owner_id: @owner.id, course_data:
      )
    end
  end

  it 'HAPPY: should be able to get list of all locations for a course' do
    course = Tyto::Course.first
    DATA[:locations].each do |loc|
      course.add_location(loc)
    end

    get "api/v1/courses/#{course.id}/locations"
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['data'].count).must_equal 2
  end

  it 'HAPPY: should be able to get details of a single location' do
    loc_data = DATA[:locations][1]
    course = Tyto::Course.first
    loc = course.add_location(loc_data)

    get "/api/v1/courses/#{course.id}/locations/#{loc.id}"
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['data']['attributes']['id']).must_equal loc.id
    _(result['data']['attributes']['name']).must_equal loc_data['name']
  end

  it 'SAD: should return error if unknown location requested' do
    course = Tyto::Course.first
    get "/api/v1/courses/#{course.id}/locations/foobar"

    _(last_response.status).must_equal 404
  end

  describe 'Creating Locations' do
    before do
      @course = Tyto::Course.first
      @loc_data = DATA[:locations][1]
      @req_header = { 'CONTENT_TYPE' => 'application/json' }
    end

    it 'HAPPY: should be able to create new locations' do
      payload = @loc_data.merge('current_account_id' => @owner.id)
      post "api/v1/courses/#{@course.id}/locations",
           payload.to_json, @req_header
      _(last_response.status).must_equal 201
      _(last_response.headers['Location'].size).must_be :>, 0

      created = JSON.parse(last_response.body)['data']['data']['attributes']
      loc = Tyto::Location.first

      _(created['id']).must_equal loc.id
      _(created['name']).must_equal @loc_data['name']
    end

    it 'SECURITY: should silently drop unknown attributes from request body' do
      bad_data = @loc_data.merge(
        'current_account_id' => @owner.id, 'created_at' => '1900-01-01'
      )
      post "api/v1/courses/#{@course.id}/locations",
           bad_data.to_json, @req_header

      _(last_response.status).must_equal 201
      loc = Tyto::Location.first
      # Route-level whitelist filtered 'created_at' before the model saw it.
      _(loc.created_at.year).wont_equal 1900
    end

    it 'SECURITY: missing current_account_id returns 401' do
      post "api/v1/courses/#{@course.id}/locations",
           @loc_data.to_json, @req_header

      _(last_response.status).must_equal 401
    end

    it 'SECURITY: non-teaching current_account_id returns 403' do
      outsider = Tyto::Account.create(DATA[:accounts][1])
      payload = @loc_data.merge('current_account_id' => outsider.id)

      post "api/v1/courses/#{@course.id}/locations",
           payload.to_json, @req_header

      _(last_response.status).must_equal 403
    end
  end
end
