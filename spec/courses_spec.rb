# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Test Course Handling' do
  include Rack::Test::Methods

  before do
    wipe_database
  end

  it 'HAPPY: should be able to get list of all courses' do
    Tyto::Course.create(DATA[:courses][0]).save_changes
    Tyto::Course.create(DATA[:courses][1]).save_changes

    get 'api/v1/courses'
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['data'].count).must_equal 2
  end

  it 'HAPPY: should be able to get details of a single course' do
    existing_course = DATA[:courses][1]
    Tyto::Course.create(existing_course).save_changes
    id = Tyto::Course.first.id

    get "/api/v1/courses/#{id}"
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['data']['attributes']['id']).must_equal id
    _(result['data']['attributes']['name']).must_equal existing_course['name']
  end

  it 'SAD: should return error if unknown course requested' do
    get '/api/v1/courses/foobar'

    _(last_response.status).must_equal 404
  end

  it 'HAPPY: should be able to create new courses' do
    existing_course = DATA[:courses][1]

    req_header = { 'CONTENT_TYPE' => 'application/json' }
    post 'api/v1/courses', existing_course.to_json, req_header
    _(last_response.status).must_equal 201
    _(last_response.headers['Location'].size).must_be :>, 0

    created = JSON.parse(last_response.body)['data']['data']['attributes']
    course = Tyto::Course.first

    _(created['id']).must_equal course.id
    _(created['name']).must_equal existing_course['name']
    _(created['description']).must_equal existing_course['description']
  end
end
