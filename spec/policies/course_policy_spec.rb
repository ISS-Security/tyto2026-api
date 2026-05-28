# frozen_string_literal: true

require_relative 'policy_helper'

describe 'CoursePolicy' do
  include PolicyWorld

  before { setup_policy_world }

  describe 'predicates by role' do
    it 'HAPPY: owner can view + edit + delete + enroll' do
      policy = Tyto::CoursePolicy.new(@creator, @course)
      _(policy.can_view?).must_equal true
      _(policy.can_edit?).must_equal true
      _(policy.can_delete?).must_equal true
      _(policy.can_enroll?).must_equal true
      _(policy.can_record_attendance?).must_equal false
    end

    it 'HAPPY: instructor can view + edit, cannot delete' do
      policy = Tyto::CoursePolicy.new(@instructor, @course)
      _(policy.can_view?).must_equal true
      _(policy.can_edit?).must_equal true
      _(policy.can_delete?).must_equal false
      _(policy.can_enroll?).must_equal true
    end

    it 'HAPPY: staff can view + edit, cannot delete' do
      policy = Tyto::CoursePolicy.new(@staff, @course)
      _(policy.can_view?).must_equal true
      _(policy.can_edit?).must_equal true
      _(policy.can_delete?).must_equal false
    end

    it 'HAPPY: student can view + record_attendance, cannot edit' do
      policy = Tyto::CoursePolicy.new(@student, @course)
      _(policy.can_view?).must_equal true
      _(policy.can_edit?).must_equal false
      _(policy.can_record_attendance?).must_equal true
    end

    it 'SAD: non-enrolled cannot view' do
      policy = Tyto::CoursePolicy.new(@outsider, @course)
      _(policy.can_view?).must_equal false
      _(policy.can_edit?).must_equal false
    end

    it 'HAPPY: admin can view + edit + delete regardless of enrollment' do
      policy = Tyto::CoursePolicy.new(@admin, @course)
      _(policy.can_view?).must_equal true
      _(policy.can_edit?).must_equal true
      _(policy.can_delete?).must_equal true
    end
  end

  describe '#summary and #index_summary' do
    it 'HAPPY: #summary returns full predicate set' do
      summary = Tyto::CoursePolicy.new(@creator, @course).summary
      _(summary.keys.sort).must_equal %i[
        can_delete can_edit can_enroll can_record_attendance can_view
      ].sort
    end

    it 'HAPPY: #index_summary returns slim set' do
      slim = Tyto::CoursePolicy.new(@creator, @course).index_summary
      _(slim.keys.sort).must_equal %i[can_edit can_view].sort
    end
  end
end
