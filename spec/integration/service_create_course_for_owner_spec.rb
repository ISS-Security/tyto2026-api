# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test CreateCourseForOwner service' do
  before do
    wipe_database

    %w[admin creator member owner instructor staff student].each do |role_name|
      Tyto::Role.find_or_create(name: role_name)
    end

    @account = Tyto::Account.create(DATA[:accounts][0])
    @account.add_system_role(Tyto::Role.first(name: 'creator'))
    @course_data = DATA[:courses][0]
  end

  it 'HAPPY: should create a course AND an owner enrollment atomically' do
    course = Tyto::CreateCourseForOwner.call(
      current_account_id: @account.id,
      owner_id: @account.id, course_data: @course_data
    )

    _(Tyto::Course.count).must_equal 1
    _(Tyto::Enrollment.count).must_equal 1
    _(course.name).must_equal @course_data['name']
    _(course.owner).must_equal @account
  end

  it 'SAD: should raise UnknownOwnerError and roll back any Course row' do
    _(proc do
      Tyto::CreateCourseForOwner.call(
        current_account_id: @account.id,
        owner_id: -1, course_data: @course_data
      )
    end).must_raise Tyto::CreateCourseForOwner::UnknownOwnerError

    _(Tyto::Course.count).must_equal 0
    _(Tyto::Enrollment.count).must_equal 0
  end

  it 'SECURITY: should raise NotAuthorizedError when actor lacks creator/admin' do
    plain_account = Tyto::Account.create(DATA[:accounts][1])

    _(proc do
      Tyto::CreateCourseForOwner.call(
        current_account_id: plain_account.id,
        owner_id: @account.id, course_data: @course_data
      )
    end).must_raise Tyto::CreateCourseForOwner::NotAuthorizedError

    _(Tyto::Course.count).must_equal 0
    _(Tyto::Enrollment.count).must_equal 0
  end

  it 'SECURITY: should raise UnknownCurrentAccountError when actor does not exist' do
    _(proc do
      Tyto::CreateCourseForOwner.call(
        current_account_id: -1,
        owner_id: @account.id, course_data: @course_data
      )
    end).must_raise Tyto::CreateCourseForOwner::UnknownCurrentAccountError
  end
end
