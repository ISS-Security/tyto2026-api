# frozen_string_literal: true

require_relative 'policy_helper'

describe 'SystemRolePolicy' do
  include PolicyWorld

  before { setup_policy_world }

  it 'HAPPY: admin can manage system roles for any account' do
    policy = Tyto::SystemRolePolicy.new(@admin, @member)
    _(policy.can_manage?).must_equal true
  end

  it 'SAD: non-admin cannot manage system roles' do
    policy = Tyto::SystemRolePolicy.new(@creator, @member)
    _(policy.can_manage?).must_equal false
  end

  it 'SAD: nil viewer is rejected' do
    policy = Tyto::SystemRolePolicy.new(nil, @member)
    _(policy.can_manage?).must_equal false
  end
end
