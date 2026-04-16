# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Event Handling' do
  include Rack::Test::Methods

  before do
    wipe_database

    DATA[:courses].each do |course_data|
      Tyto::Course.create(course_data)
    end
  end

  it 'HAPPY: should be able to get list of all events for a course' do
    course = Tyto::Course.first
    DATA[:events].each do |event|
      course.add_event(event)
    end

    get "api/v1/courses/#{course.id}/events"
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['data'].count).must_equal 2
  end

  it 'HAPPY: should be able to get details of a single event' do
    event_data = DATA[:events][1]
    course = Tyto::Course.first
    event = course.add_event(event_data)

    get "/api/v1/courses/#{course.id}/events/#{event.id}"
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['data']['attributes']['id']).must_equal event.id
    _(result['data']['attributes']['name']).must_equal event_data['name']
  end

  it 'SAD: should return error if unknown event requested' do
    course = Tyto::Course.first
    get "/api/v1/courses/#{course.id}/events/foobar"

    _(last_response.status).must_equal 404
  end

  describe 'Creating Events' do
    before do
      @course = Tyto::Course.first
      @event_data = DATA[:events][1]
      @req_header = { 'CONTENT_TYPE' => 'application/json' }
    end

    it 'HAPPY: should be able to create new events' do
      post "api/v1/courses/#{@course.id}/events",
           @event_data.to_json, @req_header
      _(last_response.status).must_equal 201
      _(last_response.headers['Location'].size).must_be :>, 0

      created = JSON.parse(last_response.body)['data']['data']['attributes']
      event = Tyto::Event.first

      _(created['id']).must_equal event.id
      _(created['name']).must_equal @event_data['name']
    end

    it 'SECURITY: should not create events with mass assignment' do
      bad_data = @event_data.clone
      bad_data['created_at'] = '1900-01-01'
      post "api/v1/courses/#{@course.id}/events",
           bad_data.to_json, @req_header

      _(last_response.status).must_equal 400
      _(last_response.headers['Location']).must_be_nil
    end
  end
end
