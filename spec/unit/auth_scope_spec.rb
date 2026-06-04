# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test AuthScope' do
  it 'AUTH SCOPE: should validate default full scope' do
    scope = Tyto::AuthScope.new
    _(scope.can_read?('*')).must_equal true
    _(scope.can_write?('*')).must_equal true
    _(scope.can_read?('attendances')).must_equal true
    _(scope.can_write?('attendances')).must_equal true
  end

  it 'AUTH SCOPE: should evaluate read-only scope' do
    scope = Tyto::AuthScope.new(Tyto::AuthScope::READ_ONLY)
    _(scope.can_read?('courses')).must_equal true
    _(scope.can_read?('attendances')).must_equal true
    _(scope.can_write?('courses')).must_equal false
    _(scope.can_write?('attendances')).must_equal false
  end

  it 'AUTH SCOPE: should validate a single limited scope' do
    scope = Tyto::AuthScope.new('attendances:read')
    _(scope.can_read?('*')).must_equal false
    _(scope.can_write?('*')).must_equal false
    _(scope.can_read?('attendances')).must_equal true
    _(scope.can_write?('attendances')).must_equal false
  end

  it 'AUTH SCOPE: should validate a list of limited scopes' do
    scope = Tyto::AuthScope.new('courses:read attendances:write')
    _(scope.can_read?('*')).must_equal false
    _(scope.can_write?('*')).must_equal false
    _(scope.can_read?('courses')).must_equal true
    _(scope.can_write?('courses')).must_equal false
    _(scope.can_read?('attendances')).must_equal true
    _(scope.can_write?('attendances')).must_equal true
  end

  it 'AUTH SCOPE: write permission implies read on the same resource' do
    scope = Tyto::AuthScope.new('courses:write')
    _(scope.can_read?('courses')).must_equal true
    _(scope.can_write?('courses')).must_equal true
  end

  it 'AUTH SCOPE: round-trips through to_s' do
    _(Tyto::AuthScope.new(Tyto::AuthScope::READ_ONLY).to_s).must_equal '*:read'
    _(Tyto::AuthScope.new.to_s).must_equal '*:write'
  end
end
