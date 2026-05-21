# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Attendance Handling' do
  include Rack::Test::Methods

  def live_event(course)
    course.add_event(
      'name' => "Live #{rand(100_000)}",
      'start_at' => Time.now - 60,
      'end_at' => Time.now + 3600
    )
  end

  def past_event(course)
    course.add_event(
      'name' => "Past #{rand(100_000)}",
      'start_at' => Time.now - 7200,
      'end_at' => Time.now - 3600
    )
  end

  before do
    wipe_database
    app.DB[:attendances].delete if app.DB.tables.include?(:attendances)

    %w[admin creator member owner instructor staff student].each do |role_name|
      Tyto::Role.find_or_create(name: role_name)
    end

    @owner = Tyto::Account.create(DATA[:accounts][0])
    @owner.add_system_role(Tyto::Role.first(name: 'creator'))
    @course = Tyto::CreateCourseForOwner.call(
      current_account_id: @owner.id, owner_id: @owner.id, course_data: DATA[:courses][0]
    )
    @student = Tyto::Account.create(DATA[:accounts][1])
    Tyto::EnrollAccountInCourse.call(
      current_account_id: @owner.id, target_account_id: @student.id,
      course_id: @course.id, role_name: 'student'
    )
    @outsider = Tyto::Account.create(DATA[:accounts][2])
  end

  describe 'Student check-in' do
    it 'HAPPY: enrolled student can check in to a live event' do
      event = live_event(@course)

      post "api/v1/courses/#{@course.id}/attendances",
           { event_id: event.id }.to_json, auth_request_header(@student)
      _(last_response.status).must_equal 201
      attendance = Tyto::Attendance.first
      _(attendance.account_id).must_equal @student.id
      _(attendance.event_id).must_equal event.id
    end

    it 'BAD: returns 403 when caller is not a student in this course' do
      event = live_event(@course)

      post "api/v1/courses/#{@course.id}/attendances",
           { event_id: event.id }.to_json, auth_request_header(@outsider)
      _(last_response.status).must_equal 403
      _(Tyto::Attendance.count).must_equal 0
    end

    it 'BAD: returns 401 without an Authorization header' do
      event = live_event(@course)

      post "api/v1/courses/#{@course.id}/attendances",
           { event_id: event.id }.to_json, { 'CONTENT_TYPE' => 'application/json' }
      _(last_response.status).must_equal 401
    end

    it 'BAD: returns 409 on duplicate check-in for same event' do
      event = live_event(@course)
      Tyto::Attendance.create(
        account_id: @student.id, event_id: event.id, course_id: @course.id,
        checked_in_at: Time.now
      )

      post "api/v1/courses/#{@course.id}/attendances",
           { event_id: event.id }.to_json, auth_request_header(@student)
      _(last_response.status).must_equal 409
    end

    it 'BAD: returns 422 when event is not live now' do
      event = past_event(@course)

      post "api/v1/courses/#{@course.id}/attendances",
           { event_id: event.id }.to_json, auth_request_header(@student)
      _(last_response.status).must_equal 422
    end

    it 'BAD: returns 404 for unknown event' do
      post "api/v1/courses/#{@course.id}/attendances",
           { event_id: 'nosuchevent' }.to_json, auth_request_header(@student)
      _(last_response.status).must_equal 404
    end
  end

  describe "List caller's own attendances" do
    it 'HAPPY: student gets their attendances for this course' do
      event1 = live_event(@course)
      event2 = past_event(@course)
      Tyto::Attendance.create(account_id: @student.id, event_id: event1.id,
                              course_id: @course.id, checked_in_at: Time.now)
      Tyto::Attendance.create(account_id: @student.id, event_id: event2.id,
                              course_id: @course.id, checked_in_at: Time.now - 3600)

      get "api/v1/courses/#{@course.id}/attendances", nil, auth_header(@student)
      _(last_response.status).must_equal 200
      _(JSON.parse(last_response.body)['data'].size).must_equal 2
    end

    it 'BAD: returns 404 when caller is not enrolled' do
      get "api/v1/courses/#{@course.id}/attendances", nil, auth_header(@outsider)
      _(last_response.status).must_equal 404
    end
  end

  describe 'Teaching staff: event attendances' do
    it 'HAPPY: owner can see all attendances for one event' do
      event = live_event(@course)
      Tyto::Attendance.create(account_id: @student.id, event_id: event.id,
                              course_id: @course.id, checked_in_at: Time.now)

      get "api/v1/courses/#{@course.id}/attendances/#{event.id}", nil, auth_header(@owner)
      _(last_response.status).must_equal 200
      _(JSON.parse(last_response.body)['data'].size).must_equal 1
    end

    it 'BAD: student gets 403 on the staff endpoint' do
      event = live_event(@course)
      get "api/v1/courses/#{@course.id}/attendances/#{event.id}", nil, auth_header(@student)
      _(last_response.status).must_equal 403
    end
  end

  describe 'Eligible events listing' do
    it 'HAPPY: returns events the caller can check in to right now' do
      live = live_event(@course)
      past_event(@course)

      get 'api/v1/attendances/eligible', nil, auth_header(@student)
      _(last_response.status).must_equal 200

      ids = JSON.parse(last_response.body)['data'].map { |e| e['attributes']['id'] }
      _(ids).must_include live.id
      _(ids.size).must_equal 1
    end

    it 'HAPPY: filters out events the caller has already attended' do
      live = live_event(@course)
      Tyto::Attendance.create(account_id: @student.id, event_id: live.id,
                              course_id: @course.id, checked_in_at: Time.now)

      get 'api/v1/attendances/eligible', nil, auth_header(@student)
      _(last_response.status).must_equal 200
      _(JSON.parse(last_response.body)['data']).must_equal []
    end

    it 'BAD: returns empty list for a non-student' do
      live_event(@course)
      get 'api/v1/attendances/eligible', nil, auth_header(@outsider)
      _(last_response.status).must_equal 200
      _(JSON.parse(last_response.body)['data']).must_equal []
    end

    it 'BAD: returns 401 without Authorization header' do
      get 'api/v1/attendances/eligible'
      _(last_response.status).must_equal 401
    end
  end
end
