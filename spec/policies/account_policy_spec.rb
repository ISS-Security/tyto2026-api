# frozen_string_literal: true

require_relative 'policy_helper'

describe 'AccountPolicy' do
  include PolicyWorld

  before { setup_policy_world }

  describe 'actor-scoped predicates (capabilities)' do
    it 'HAPPY: admin → is_admin, can_create_course, can_manage_system_roles' do
      caps = Tyto::AccountPolicy.new(@admin).capabilities
      _(caps[:is_admin]).must_equal true
      _(caps[:can_create_course]).must_equal true
      _(caps[:can_manage_system_roles]).must_equal true
    end

    it 'HAPPY: creator → can_create_course only' do
      caps = Tyto::AccountPolicy.new(@creator).capabilities
      _(caps[:is_admin]).must_equal false
      _(caps[:can_create_course]).must_equal true
      _(caps[:can_manage_system_roles]).must_equal false
    end

    it 'HAPPY: member → no actor capabilities' do
      caps = Tyto::AccountPolicy.new(@member).capabilities
      _(caps.values).must_equal [false, false, false]
    end
  end

  describe 'entity-scoped predicates (summary)' do
    it 'HAPPY: self viewing self can edit, cannot assign roles' do
      summary = Tyto::AccountPolicy.new(@member, @member).summary
      _(summary[:can_view]).must_equal true
      _(summary[:can_edit]).must_equal true
      _(summary[:can_assign_role]).must_equal false
      _(summary[:can_delete]).must_equal false
    end

    it 'HAPPY: admin viewing other can edit + assign + revoke' do
      summary = Tyto::AccountPolicy.new(@admin, @member).summary
      _(summary[:can_edit]).must_equal true
      _(summary[:can_assign_role]).must_equal true
      _(summary[:can_revoke_role]).must_equal true
      _(summary[:can_delete]).must_equal true
    end

    it 'SAD: non-admin viewing other cannot view or edit' do
      summary = Tyto::AccountPolicy.new(@member, @creator).summary
      _(summary[:can_view]).must_equal false
      _(summary[:can_edit]).must_equal false
    end
  end
end
