# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Event Handling' do
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

  it 'HAPPY: should be able to get list of all events for a course' do
    course = Tyto::Course.first
    DATA[:events].each do |event|
      course.add_event(event)
    end

    get "api/v1/courses/#{course.id}/events", nil, auth_header(@owner)
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['data'].count).must_equal 2
    _(result['data'].first['type']).must_equal 'event'
  end

  it 'HAPPY: should be able to get details of a single event' do
    event_data = DATA[:events][1]
    course = Tyto::Course.first
    event = course.add_event(event_data)

    get "/api/v1/courses/#{course.id}/events/#{event.id}", nil, auth_header(@owner)
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['type']).must_equal 'event'
    _(result['attributes']['id']).must_equal event.id
    _(result['attributes']['name']).must_equal event_data['name']
    _(result['include']).wont_be_nil
  end

  it 'SAD: should return error if unknown event requested' do
    course = Tyto::Course.first
    get "/api/v1/courses/#{course.id}/events/foobar", nil, auth_header(@owner)

    _(last_response.status).must_equal 404
  end

  it 'SECURITY: events list returns 401 when Authorization missing' do
    course = Tyto::Course.first
    get "api/v1/courses/#{course.id}/events"
    _(last_response.status).must_equal 401
  end

  it 'SECURITY: events list returns 404 when caller is not enrolled' do
    course = Tyto::Course.first
    outsider = Tyto::Account.create(DATA[:accounts][1])
    get "api/v1/courses/#{course.id}/events", nil, auth_header(outsider)
    _(last_response.status).must_equal 404
  end

  describe 'Creating Events' do
    before do
      @course = Tyto::Course.first
      @event_data = DATA[:events][1]
    end

    it 'HAPPY: should be able to create new events' do
      post "api/v1/courses/#{@course.id}/events",
           @event_data.to_json, auth_request_header(@owner)
      _(last_response.status).must_equal 201
      _(last_response.headers['Location'].size).must_be :>, 0

      created = JSON.parse(last_response.body)['data']['attributes']
      event = Tyto::Event.first

      _(created['id']).must_equal event.id
      _(created['name']).must_equal @event_data['name']
    end

    it 'SECURITY: should silently drop unknown attributes from request body' do
      bad_data = @event_data.merge('created_at' => '1900-01-01')
      post "api/v1/courses/#{@course.id}/events",
           bad_data.to_json, auth_request_header(@owner)

      _(last_response.status).must_equal 201
      event = Tyto::Event.first
      # Route-level whitelist filtered 'created_at' before the model saw it.
      _(event.created_at.year).wont_equal 1900
    end

    it 'SECURITY: missing Authorization header returns 401' do
      post "api/v1/courses/#{@course.id}/events",
           @event_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      _(last_response.status).must_equal 401
    end

    it 'SECURITY: non-teaching caller returns 403' do
      outsider = Tyto::Account.create(DATA[:accounts][1])

      post "api/v1/courses/#{@course.id}/events",
           @event_data.to_json, auth_request_header(outsider)

      _(last_response.status).must_equal 403
    end
  end
end
