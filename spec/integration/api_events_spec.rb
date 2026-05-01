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

    get "api/v1/courses/#{course.id}/events?current_account_id=#{@owner.id}"
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['data'].count).must_equal 2
    _(result['data'].first['type']).must_equal 'event'
  end

  it 'HAPPY: should be able to get details of a single event' do
    event_data = DATA[:events][1]
    course = Tyto::Course.first
    event = course.add_event(event_data)

    get "/api/v1/courses/#{course.id}/events/#{event.id}?current_account_id=#{@owner.id}"
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['type']).must_equal 'event'
    _(result['attributes']['id']).must_equal event.id
    _(result['attributes']['name']).must_equal event_data['name']
    _(result['include']).wont_be_nil
  end

  it 'SAD: should return error if unknown event requested' do
    course = Tyto::Course.first
    get "/api/v1/courses/#{course.id}/events/foobar?current_account_id=#{@owner.id}"

    _(last_response.status).must_equal 404
  end

  it 'SECURITY: events list returns 401 when current_account_id missing' do
    course = Tyto::Course.first
    get "api/v1/courses/#{course.id}/events"
    _(last_response.status).must_equal 401
  end

  it 'SECURITY: events list returns 404 when current_account_id is not enrolled' do
    course = Tyto::Course.first
    outsider = Tyto::Account.create(DATA[:accounts][1])
    get "api/v1/courses/#{course.id}/events?current_account_id=#{outsider.id}"
    _(last_response.status).must_equal 404
  end

  describe 'Creating Events' do
    before do
      @course = Tyto::Course.first
      @event_data = DATA[:events][1]
      @req_header = { 'CONTENT_TYPE' => 'application/json' }
    end

    it 'HAPPY: should be able to create new events' do
      payload = @event_data.merge('current_account_id' => @owner.id)
      post "api/v1/courses/#{@course.id}/events",
           payload.to_json, @req_header
      _(last_response.status).must_equal 201
      _(last_response.headers['Location'].size).must_be :>, 0

      created = JSON.parse(last_response.body)['data']['attributes']
      event = Tyto::Event.first

      _(created['id']).must_equal event.id
      _(created['name']).must_equal @event_data['name']
    end

    it 'SECURITY: should silently drop unknown attributes from request body' do
      bad_data = @event_data.merge(
        'current_account_id' => @owner.id, 'created_at' => '1900-01-01'
      )
      post "api/v1/courses/#{@course.id}/events",
           bad_data.to_json, @req_header

      _(last_response.status).must_equal 201
      event = Tyto::Event.first
      # Route-level whitelist filtered 'created_at' before the model saw it.
      _(event.created_at.year).wont_equal 1900
    end

    it 'SECURITY: missing current_account_id returns 401' do
      post "api/v1/courses/#{@course.id}/events",
           @event_data.to_json, @req_header

      _(last_response.status).must_equal 401
    end

    it 'SECURITY: non-teaching current_account_id returns 403' do
      outsider = Tyto::Account.create(DATA[:accounts][1])
      payload = @event_data.merge('current_account_id' => outsider.id)

      post "api/v1/courses/#{@course.id}/events",
           payload.to_json, @req_header

      _(last_response.status).must_equal 403
    end
  end
end
