# frozen_string_literal: true

require_relative 'policy_helper'

describe 'LocationPolicy' do
  include PolicyWorld

  before { setup_policy_world }

  it 'HAPPY: teaching staff can edit + delete' do
    policy = Tyto::LocationPolicy.new(@instructor, @location)
    _(policy.can_view?).must_equal true
    _(policy.can_edit?).must_equal true
    _(policy.can_delete?).must_equal true
  end

  it 'HAPPY: student can view, cannot edit' do
    policy = Tyto::LocationPolicy.new(@student, @location)
    _(policy.can_view?).must_equal true
    _(policy.can_edit?).must_equal false
  end

  it 'SAD: outsider cannot view' do
    policy = Tyto::LocationPolicy.new(@outsider, @location)
    _(policy.can_view?).must_equal false
  end
end
