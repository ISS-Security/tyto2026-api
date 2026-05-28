# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Role instance predicates' do
  before do
    wipe_database
    %w[admin creator member owner instructor staff student].each do |n|
      Tyto::Role.find_or_create(name: n)
    end
  end

  it 'HAPPY: system-role predicates match name' do
    _(Tyto::Role.first(name: 'admin').admin?).must_equal true
    _(Tyto::Role.first(name: 'creator').creator?).must_equal true
    _(Tyto::Role.first(name: 'member').member?).must_equal true
  end

  it 'HAPPY: course-role predicates match name' do
    _(Tyto::Role.first(name: 'owner').owner?).must_equal true
    _(Tyto::Role.first(name: 'instructor').instructor?).must_equal true
    _(Tyto::Role.first(name: 'staff').staff?).must_equal true
    _(Tyto::Role.first(name: 'student').student?).must_equal true
  end

  it 'HAPPY: teaching? matches owner, instructor, staff' do
    %w[owner instructor staff].each do |n|
      _(Tyto::Role.first(name: n).teaching?).must_equal true
    end
    _(Tyto::Role.first(name: 'student').teaching?).must_equal false
  end

  it 'HAPPY: course_creator? matches creator and admin' do
    _(Tyto::Role.first(name: 'creator').course_creator?).must_equal true
    _(Tyto::Role.first(name: 'admin').course_creator?).must_equal true
    _(Tyto::Role.first(name: 'member').course_creator?).must_equal false
  end

  it 'SAD: predicates do not cross categories' do
    _(Tyto::Role.first(name: 'admin').student?).must_equal false
    _(Tyto::Role.first(name: 'owner').admin?).must_equal false
  end
end
