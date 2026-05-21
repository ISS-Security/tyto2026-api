# frozen_string_literal: true

require_relative 'policy_helper'

describe 'EventPolicy' do
  include PolicyWorld

  before { setup_policy_world }

  it 'HAPPY: teaching staff can edit + delete' do
    policy = Tyto::EventPolicy.new(@instructor, @live_event)
    _(policy.can_view?).must_equal true
    _(policy.can_edit?).must_equal true
    _(policy.can_delete?).must_equal true
  end

  it 'HAPPY: student can view + record_attendance on a live event' do
    policy = Tyto::EventPolicy.new(@student, @live_event)
    _(policy.can_view?).must_equal true
    _(policy.can_edit?).must_equal false
    _(policy.can_record_attendance?).must_equal true
  end

  it 'SAD: student cannot record_attendance on a future event' do
    policy = Tyto::EventPolicy.new(@student, @future_event)
    _(policy.can_record_attendance?).must_equal false
  end

  it 'SAD: outsider cannot view' do
    policy = Tyto::EventPolicy.new(@outsider, @live_event)
    _(policy.can_view?).must_equal false
  end
end

describe 'EventPolicy::CourseScope' do
  include PolicyWorld

  before { setup_policy_world }

  it 'HAPPY: enrolled student sees the course events' do
    events = Tyto::EventPolicy::CourseScope.new(@student, @course).viewable
    _(events.map(&:id)).must_include @live_event.id
  end

  it 'SAD: outsider sees no events for the course' do
    events = Tyto::EventPolicy::CourseScope.new(@outsider, @course).viewable
    _(events).must_equal []
  end
end
