# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Course Handling' do
  include Rack::Test::Methods

  before do
    wipe_database
  end

  describe 'Getting courses' do
    it 'HAPPY: should be able to get list of all courses' do
      Tyto::Course.create(DATA[:courses][0])
      Tyto::Course.create(DATA[:courses][1])

      get 'api/v1/courses'
      _(last_response.status).must_equal 200

      result = JSON.parse last_response.body
      _(result['data'].count).must_equal 2
    end

    it 'HAPPY: should be able to get details of a single course' do
      existing_course = DATA[:courses][1]
      Tyto::Course.create(existing_course)
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

    it 'SECURITY: should prevent basic SQL injection targeting IDs' do
      Tyto::Course.create(name: 'First Course')
      Tyto::Course.create(name: 'Second Course')
      get 'api/v1/courses/2%20or%20id%3E0'

      # deliberately not reporting error -- don't give attacker information
      _(last_response.status).must_equal 404
      _(last_response.body['data']).must_be_nil
    end
  end

  describe 'Creating New Courses' do
    before do
      @req_header = { 'CONTENT_TYPE' => 'application/json' }
      @course_data = DATA[:courses][1]
    end

    it 'HAPPY: should be able to create new courses' do
      post 'api/v1/courses', @course_data.to_json, @req_header
      _(last_response.status).must_equal 201
      _(last_response.headers['Location'].size).must_be :>, 0

      created = JSON.parse(last_response.body)['data']['data']['attributes']
      course = Tyto::Course.first

      _(created['id']).must_equal course.id
      _(created['name']).must_equal @course_data['name']
      _(created['description']).must_equal @course_data['description']
    end

    it 'SECURITY: should not create course with mass assignment' do
      bad_data = @course_data.clone
      bad_data['created_at'] = '1900-01-01'
      post 'api/v1/courses', bad_data.to_json, @req_header

      _(last_response.status).must_equal 400
      _(last_response.headers['Location']).must_be_nil
    end
  end
end
