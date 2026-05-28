# frozen_string_literal: true

require_relative 'policy_helper'

describe 'EnrollmentPolicy' do
  include PolicyWorld

  before { setup_policy_world }

  it 'HAPPY: instructor can manage enrollments' do
    policy = Tyto::EnrollmentPolicy.new(@instructor, @course)
    _(policy.can_manage?).must_equal true
  end

  it 'SAD: student cannot manage enrollments' do
    policy = Tyto::EnrollmentPolicy.new(@student, @course)
    _(policy.can_manage?).must_equal false
  end

  it 'HAPPY: student can leave their own non-owner enrollment' do
    enrollment = Tyto::Enrollment.first(account_id: @student.id, course_id: @course.id)
    policy = Tyto::EnrollmentPolicy.new(@student, enrollment)
    _(policy.can_leave?).must_equal true
  end

  it 'SAD: owner cannot leave their own owner enrollment' do
    enrollment = Tyto::Enrollment.first(
      account_id: @creator.id, course_id: @course.id,
      role_id: Tyto::Role.id_for('owner')
    )
    policy = Tyto::EnrollmentPolicy.new(@creator, enrollment)
    _(policy.can_leave?).must_equal false
  end
end
