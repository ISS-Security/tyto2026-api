# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Course Handling' do
  include Rack::Test::Methods

  before do
    wipe_database
  end

  describe 'Getting courses' do
    before do
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

    it 'HAPPY: should return only courses the current_account is enrolled in' do
      get "api/v1/courses?current_account_id=#{@owner.id}"
      _(last_response.status).must_equal 200

      result = JSON.parse last_response.body
      _(result['data'].count).must_equal DATA[:courses].size
      _(result['data'].first['type']).must_equal 'course'
      _(result['data'].first['attributes']['name']).wont_be_nil
    end

    it 'HAPPY: should return empty list for an account with no enrollments' do
      outsider = Tyto::Account.create(DATA[:accounts][1])

      get "api/v1/courses?current_account_id=#{outsider.id}"
      _(last_response.status).must_equal 200
      _(JSON.parse(last_response.body)['data']).must_equal []
    end

    it 'SECURITY: missing current_account_id returns 401' do
      get 'api/v1/courses'
      _(last_response.status).must_equal 401
    end

    it 'HAPPY: should be able to get details of a single course' do
      existing = Tyto::Course.first

      get "/api/v1/courses/#{existing.id}?current_account_id=#{@owner.id}"
      _(last_response.status).must_equal 200

      result = JSON.parse last_response.body
      _(result['type']).must_equal 'course'
      _(result['attributes']['id']).must_equal existing.id
      _(result['attributes']['name']).must_equal existing.name
    end

    it 'SAD: should return error if unknown course requested' do
      get "/api/v1/courses/foobar?current_account_id=#{@owner.id}"

      _(last_response.status).must_equal 404
    end

    it 'SECURITY: detail returns 401 when current_account_id missing' do
      existing = Tyto::Course.first
      get "/api/v1/courses/#{existing.id}"
      _(last_response.status).must_equal 401
    end

    it 'SECURITY: detail returns 404 when current_account_id is not enrolled' do
      existing = Tyto::Course.first
      outsider = Tyto::Account.create(DATA[:accounts][1])
      get "/api/v1/courses/#{existing.id}?current_account_id=#{outsider.id}"
      _(last_response.status).must_equal 404
    end

    it 'SECURITY: should prevent basic SQL injection targeting IDs' do
      get "api/v1/courses/2%20or%20id%3E0?current_account_id=#{@owner.id}"

      # deliberately not reporting error -- don't give attacker information
      _(last_response.status).must_equal 404
      _(last_response.body['data']).must_be_nil
    end
  end

  describe 'Creating New Courses' do
    before do
      %w[admin creator member owner instructor staff student].each do |role_name|
        Tyto::Role.find_or_create(name: role_name)
      end

      @req_header = { 'CONTENT_TYPE' => 'application/json' }
      @course_data = DATA[:courses][1]
      @creator = Tyto::Account.create(DATA[:accounts][0])
      @creator.add_system_role(Tyto::Role.first(name: 'creator'))
    end

    it 'HAPPY: should be able to create new courses and enroll the creator as owner' do
      body = @course_data.merge(current_account_id: @creator.id)
      post 'api/v1/courses', body.to_json, @req_header
      _(last_response.status).must_equal 201
      _(last_response.headers['Location'].size).must_be :>, 0

      created = JSON.parse(last_response.body)['data']['attributes']
      course = Tyto::Course.first

      _(created['id']).must_equal course.id
      _(created['name']).must_equal @course_data['name']
      _(created['description']).must_equal @course_data['description']

      enrollments = course.enrollments
      _(enrollments.size).must_equal 1
      _(enrollments.first.account_id).must_equal @creator.id
      _(enrollments.first.role.name).must_equal 'owner'
    end

    it 'HAPPY: admin without creator role should also be able to create courses' do
      admin = Tyto::Account.create(DATA[:accounts][2])
      admin.add_system_role(Tyto::Role.first(name: 'admin'))
      body = @course_data.merge(current_account_id: admin.id)
      post 'api/v1/courses', body.to_json, @req_header

      _(last_response.status).must_equal 201
      course = Tyto::Course.first
      _(course.enrollments.first.account_id).must_equal admin.id
    end

    it 'SECURITY: should silently strip mass-assignment attempts at the route boundary' do
      bad_data = @course_data.merge('created_at' => '1900-01-01', current_account_id: @creator.id)
      post 'api/v1/courses', bad_data.to_json, @req_header

      _(last_response.status).must_equal 201
      course = Tyto::Course.first
      _(course.created_at).must_be :>, Time.now - 60
    end

    it 'SECURITY: should reject creation without current_account_id' do
      post 'api/v1/courses', @course_data.to_json, @req_header
      _(last_response.status).must_equal 401
      _(Tyto::Course.count).must_equal 0
    end

    it 'SECURITY: account with no system roles should be denied' do
      member = Tyto::Account.create(DATA[:accounts][1])
      body = @course_data.merge(current_account_id: member.id)
      post 'api/v1/courses', body.to_json, @req_header

      _(last_response.status).must_equal 403
      _(Tyto::Course.count).must_equal 0
    end

    it 'SECURITY: member-only account should be denied' do
      member = Tyto::Account.create(DATA[:accounts][1])
      member.add_system_role(Tyto::Role.first(name: 'member'))
      body = @course_data.merge(current_account_id: member.id)
      post 'api/v1/courses', body.to_json, @req_header

      _(last_response.status).must_equal 403
      _(Tyto::Course.count).must_equal 0
    end
  end
end
