# frozen_string_literal: true

require_relative 'policy_helper'

describe 'AttendancePolicy' do
  include PolicyWorld

  before { setup_policy_world }

  describe '#can_record?' do
    it 'HAPPY: enrolled student can record on a live event' do
      policy = Tyto::AttendancePolicy.new(@student, @live_event)
      _(policy.can_record?).must_equal true
    end

    it 'SAD: future event blocks recording' do
      policy = Tyto::AttendancePolicy.new(@student, @future_event)
      _(policy.can_record?).must_equal false
    end

    it 'SAD: non-student enrolled (instructor) cannot record' do
      policy = Tyto::AttendancePolicy.new(@instructor, @live_event)
      _(policy.can_record?).must_equal false
    end

    it 'SAD: outsider cannot record' do
      policy = Tyto::AttendancePolicy.new(@outsider, @live_event)
      _(policy.can_record?).must_equal false
    end
  end

  describe 'on Attendance rows' do
    before do
      @attendance = Tyto::Attendance.create(
        account_id: @student.id,
        event_id: @live_event.id,
        course_id: @course.id,
        checked_in_at: Time.now
      )
    end

    it 'HAPPY: student can view own attendance' do
      policy = Tyto::AttendancePolicy.new(@student, @attendance)
      _(policy.can_view?).must_equal true
      _(policy.can_manage?).must_equal false
    end

    it 'HAPPY: teaching staff can view + manage' do
      policy = Tyto::AttendancePolicy.new(@instructor, @attendance)
      _(policy.can_view?).must_equal true
      _(policy.can_manage?).must_equal true
    end
  end
end

describe 'AttendancePolicy::EligibleScope' do
  include PolicyWorld

  before { setup_policy_world }

  it 'HAPPY: student gets live events they have not attended' do
    events = Tyto::AttendancePolicy::EligibleScope.new(@student).events
    _(events.map(&:id)).must_include @live_event.id
  end

  it 'SAD: future events are filtered out' do
    events = Tyto::AttendancePolicy::EligibleScope.new(@student).events
    _(events.map(&:id)).wont_include @future_event.id
  end

  it 'SAD: non-student gets empty list' do
    events = Tyto::AttendancePolicy::EligibleScope.new(@instructor).events
    _(events).must_equal []
  end

  it 'SAD: already-attended events are excluded' do
    Tyto::Attendance.create(
      account_id: @student.id, event_id: @live_event.id,
      course_id: @course.id, checked_in_at: Time.now
    )
    events = Tyto::AttendancePolicy::EligibleScope.new(@student).events
    _(events.map(&:id)).wont_include @live_event.id
  end
end
