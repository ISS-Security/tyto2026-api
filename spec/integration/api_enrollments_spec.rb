# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Enrollment Handling' do
  include Rack::Test::Methods

  before do
    wipe_database

    %w[admin creator member owner instructor staff student].each do |role_name|
      Tyto::Role.find_or_create(name: role_name)
    end

    @owner = Tyto::Account.create(DATA[:accounts][0])
    @owner.add_system_role(Tyto::Role.first(name: 'creator'))
    @student = Tyto::Account.create(DATA[:accounts][1])
    @course = Tyto::CreateCourseForOwner.call(
      current_account_id: @owner.id, owner_id: @owner.id, course_data: DATA[:courses][0]
    )
  end

  describe 'Listing enrollments' do
    it 'HAPPY: should list enrollments for a course' do
      Tyto::EnrollAccountInCourse.call(
        current_account_id: @owner.id, target_account_id: @student.id,
        course_id: @course.id, role_name: 'student'
      )

      get "api/v1/courses/#{@course.id}/enrollments", nil, auth_header(@owner)
      _(last_response.status).must_equal 200

      result = JSON.parse(last_response.body)
      _(result['data'].count).must_equal 2
      _(result['data'].first['type']).must_equal 'enrollment'
      _(result['data'].first['attributes']['role']).wont_be_nil
      _(result['data'].first['include']['account']['username']).wont_be_nil
    end

    it 'SECURITY: enrollments list returns 401 when Authorization missing' do
      get "api/v1/courses/#{@course.id}/enrollments"
      _(last_response.status).must_equal 401
    end

    it 'SECURITY: enrollments list returns 404 when caller is not enrolled' do
      outsider = Tyto::Account.create(DATA[:accounts][2])
      get "api/v1/courses/#{@course.id}/enrollments", nil, auth_header(outsider)
      _(last_response.status).must_equal 404
    end
  end

  describe 'Creating enrollments' do
    it 'HAPPY: should create a student enrollment' do
      post(
        "api/v1/courses/#{@course.id}/enrollments/#{@student.username}",
        { role_name: 'student' }.to_json,
        auth_request_header(@owner)
      )
      _(last_response.status).must_equal 201
      _(last_response.headers['Location'].size).must_be :>, 0

      _(@course.reload.students).must_include @student
    end

    it 'SAD: should 404 on unknown username' do
      post(
        "api/v1/courses/#{@course.id}/enrollments/nosuchuser",
        { role_name: 'student' }.to_json,
        auth_request_header(@owner)
      )
      _(last_response.status).must_equal 404
    end

    it 'SAD: should 400 on unknown role_name' do
      post(
        "api/v1/courses/#{@course.id}/enrollments/#{@student.username}",
        { role_name: 'supreme_leader' }.to_json,
        auth_request_header(@owner)
      )
      _(last_response.status).must_equal 400
    end

    it 'BAD: should 400 when smuggling a system role into a course enrollment' do
      post(
        "api/v1/courses/#{@course.id}/enrollments/#{@student.username}",
        { role_name: 'admin' }.to_json,
        auth_request_header(@owner)
      )
      _(last_response.status).must_equal 400
      _(Tyto::Enrollment.where(account_id: @student.id, course_id: @course.id).count).must_equal 0
    end

    it 'SAD: should 409 on duplicate (account, course, role) triple' do
      Tyto::EnrollAccountInCourse.call(
        current_account_id: @owner.id, target_account_id: @student.id,
        course_id: @course.id, role_name: 'student'
      )

      post(
        "api/v1/courses/#{@course.id}/enrollments/#{@student.username}",
        { role_name: 'student' }.to_json,
        auth_request_header(@owner)
      )
      _(last_response.status).must_equal 409
    end

    it 'SECURITY: missing Authorization header returns 401' do
      post(
        "api/v1/courses/#{@course.id}/enrollments/#{@student.username}",
        { role_name: 'student' }.to_json,
        { 'CONTENT_TYPE' => 'application/json' }
      )
      _(last_response.status).must_equal 401
    end

    it 'SECURITY: non-teaching caller returns 403' do
      post(
        "api/v1/courses/#{@course.id}/enrollments/#{@student.username}",
        { role_name: 'student' }.to_json,
        auth_request_header(@student)
      )
      _(last_response.status).must_equal 403
    end
  end

  describe 'Deleting enrollments' do
    before do
      @enrollment = Tyto::EnrollAccountInCourse.call(
        current_account_id: @owner.id, target_account_id: @student.id,
        course_id: @course.id, role_name: 'student'
      )
    end

    it 'HAPPY: should remove an enrollment' do
      delete(
        "api/v1/courses/#{@course.id}/enrollments/#{@enrollment.id}",
        nil,
        auth_header(@owner)
      )
      _(last_response.status).must_equal 200
      _(Tyto::Enrollment.first(id: @enrollment.id)).must_be_nil
      _(@course.reload.students).wont_include @student
    end

    it 'SAD: should 404 when enrollment_id belongs to a different course' do
      other_course = Tyto::CreateCourseForOwner.call(
        current_account_id: @owner.id,
        owner_id: @owner.id, course_data: DATA[:courses][1]
      )

      delete(
        "api/v1/courses/#{other_course.id}/enrollments/#{@enrollment.id}",
        nil,
        auth_header(@owner)
      )
      _(last_response.status).must_equal 404
      _(Tyto::Enrollment.first(id: @enrollment.id)).wont_be_nil
    end

    it 'SAD: should 404 for nonexistent enrollment_id' do
      delete(
        "api/v1/courses/#{@course.id}/enrollments/999999",
        nil,
        auth_header(@owner)
      )
      _(last_response.status).must_equal 404
    end

    it 'SECURITY: delete returns 401 when Authorization missing' do
      delete "api/v1/courses/#{@course.id}/enrollments/#{@enrollment.id}"
      _(last_response.status).must_equal 401
    end

    it 'SECURITY: delete returns 403 when caller is not teaching staff' do
      delete(
        "api/v1/courses/#{@course.id}/enrollments/#{@enrollment.id}",
        nil,
        auth_header(@student)
      )
      _(last_response.status).must_equal 403
      _(Tyto::Enrollment.first(id: @enrollment.id)).wont_be_nil
    end
  end

  describe 'Mass-assignment defense' do
    it 'SECURITY: whitelist_security blocks setting internal columns' do
      _(proc do
        Tyto::Enrollment.new(
          account_id: @student.id,
          course_id: @course.id,
          role_id: Tyto::Role.first(name: 'student').id,
          created_at: Time.new(1900, 1, 1)
        )
      end).must_raise Sequel::MassAssignmentRestriction
    end
  end
end
