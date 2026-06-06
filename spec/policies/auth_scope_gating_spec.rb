# frozen_string_literal: true

require_relative 'policy_helper'

# A READ_ONLY token must never authorize a write, even when the underlying
# account holds write-capable roles. Reads stay allowed. Threading no scope
# (the default FULL) restores pure role-based behavior, exercised elsewhere.
describe 'AuthScope gating in policies' do
  include PolicyWorld

  before { setup_policy_world }

  let(:read_only) { Tyto::AuthScope.new(Tyto::AuthScope::READ_ONLY) }
  let(:full) { Tyto::AuthScope.new }

  it 'COURSE: read-only lets an owner view but not edit/delete/enroll' do
    policy = Tyto::CoursePolicy.new(@creator, @course, auth_scope: read_only)
    _(policy.can_view?).must_equal true
    _(policy.can_edit?).must_equal false
    _(policy.can_delete?).must_equal false
    _(policy.can_enroll?).must_equal false
  end

  it 'COURSE: full scope restores role-based writes for an owner' do
    policy = Tyto::CoursePolicy.new(@creator, @course, auth_scope: full)
    _(policy.can_edit?).must_equal true
    _(policy.can_delete?).must_equal true
  end

  it 'EVENT: read-only denies edit/delete, allows view for teaching staff' do
    policy = Tyto::EventPolicy.new(@instructor, @live_event, auth_scope: read_only)
    _(policy.can_view?).must_equal true
    _(policy.can_edit?).must_equal false
    _(policy.can_delete?).must_equal false
  end

  it 'LOCATION: read-only denies edit, allows view for teaching staff' do
    policy = Tyto::LocationPolicy.new(@instructor, @location, auth_scope: read_only)
    _(policy.can_view?).must_equal true
    _(policy.can_edit?).must_equal false
  end

  it 'ATTENDANCE: read-only denies recording; full scope allows it' do
    _(Tyto::AttendancePolicy.new(@student, @live_event, auth_scope: read_only).can_record?).must_equal false
    _(Tyto::AttendancePolicy.new(@student, @live_event, auth_scope: full).can_record?).must_equal true
  end

  it 'ENROLLMENT: read-only denies manage; full scope allows it for staff' do
    _(Tyto::EnrollmentPolicy.new(@instructor, @course, auth_scope: read_only).can_manage?).must_equal false
    _(Tyto::EnrollmentPolicy.new(@instructor, @course, auth_scope: full).can_manage?).must_equal true
  end

  it 'ACCOUNT: read-only lets an admin view and index but not write' do
    policy = Tyto::AccountPolicy.new(@admin, @member, auth_scope: read_only)
    _(policy.can_view?).must_equal true
    _(policy.can_index_all?).must_equal true
    _(policy.can_edit?).must_equal false
    _(policy.can_delete?).must_equal false
    _(policy.can_assign_role?).must_equal false
    _(policy.can_revoke_role?).must_equal false
    _(policy.can_manage_system_roles?).must_equal false
  end

  it 'ACCOUNT: full scope restores role-based writes for an admin' do
    policy = Tyto::AccountPolicy.new(@admin, @member, auth_scope: full)
    _(policy.can_index_all?).must_equal true
    _(policy.can_edit?).must_equal true
    _(policy.can_assign_role?).must_equal true
    _(policy.can_revoke_role?).must_equal true
    _(policy.can_manage_system_roles?).must_equal true
  end

  it 'ACCOUNT: index stays admin-only even with full scope' do
    _(Tyto::AccountPolicy.new(@member, @member, auth_scope: full).can_index_all?).must_equal false
  end

  it 'SYSTEM ROLE: read-only denies manage for an admin; full scope allows it' do
    _(Tyto::SystemRolePolicy.new(@admin, @member, auth_scope: read_only).can_manage?).must_equal false
    _(Tyto::SystemRolePolicy.new(@admin, @member, auth_scope: full).can_manage?).must_equal true
  end
end
