# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Account Handling' do
  include Rack::Test::Methods

  before do
    wipe_database
    @req_header = { 'CONTENT_TYPE' => 'application/json' }
  end

  describe 'Account information' do
    it 'HAPPY: should be able to get details of a single account (no enrollments)' do
      account_data = DATA[:accounts][1]
      account = Tyto::Account.create(account_data)

      get "/api/v1/accounts/#{account.username}?current_account_id=#{account.id}"
      _(last_response.status).must_equal 200

      result = JSON.parse last_response.body
      _(result['type']).must_equal 'account'

      attrs = result['attributes']
      _(attrs['id']).must_equal account.id
      _(attrs['username']).must_equal account.username
      _(attrs['email']).must_equal account.email
      _(attrs['salt']).must_be_nil
      _(attrs['password']).must_be_nil
      _(attrs['password_hash']).must_be_nil
      _(attrs['password_digest']).must_be_nil
      _(attrs['email_secure']).must_be_nil
      _(attrs['email_hash']).must_be_nil

      _(result['include']['enrollments']).must_equal []
      _(result['include']['system_roles']).must_equal []
    end

    it 'HAPPY: should embed system roles and enrollments in account details' do
      %w[admin creator member owner instructor staff student].each do |role_name|
        Tyto::Role.find_or_create(name: role_name)
      end

      owner = Tyto::Account.create(DATA[:accounts][0])
      owner.add_system_role(Tyto::Role.first(name: 'creator'))
      course = Tyto::CreateCourseForOwner.call(
        current_account_id: owner.id, owner_id: owner.id, course_data: DATA[:courses][0]
      )

      get "/api/v1/accounts/#{owner.username}?current_account_id=#{owner.id}"
      _(last_response.status).must_equal 200

      include_block = JSON.parse(last_response.body)['include']
      _(include_block['system_roles']).must_equal ['creator']

      enrollments = include_block['enrollments']
      _(enrollments.size).must_equal 1
      _(enrollments.first['course_id']).must_equal course.id
      _(enrollments.first['course_name']).must_equal course.name
      _(enrollments.first['role']).must_equal 'owner'
    end

    it 'SAD: should return 404 for unknown username' do
      requester = Tyto::Account.create(DATA[:accounts][0])
      get "/api/v1/accounts/nosuchuser?current_account_id=#{requester.id}"
      _(last_response.status).must_equal 404
    end

    it 'SECURITY: missing current_account_id returns 401' do
      account = Tyto::Account.create(DATA[:accounts][1])
      get "/api/v1/accounts/#{account.username}"
      _(last_response.status).must_equal 401
    end

    it 'SECURITY: returns 404 when current_account_id does not match the requested account' do
      target = Tyto::Account.create(DATA[:accounts][0])
      requester = Tyto::Account.create(DATA[:accounts][1])
      get "/api/v1/accounts/#{target.username}?current_account_id=#{requester.id}"
      _(last_response.status).must_equal 404
    end

    it 'HAPPY: admin should be able to view any account' do
      %w[admin].each { |r| Tyto::Role.find_or_create(name: r) }

      target = Tyto::Account.create(DATA[:accounts][0])
      admin = Tyto::Account.create(DATA[:accounts][1])
      admin.add_system_role(Tyto::Role.first(name: 'admin'))

      get "/api/v1/accounts/#{target.username}?current_account_id=#{admin.id}"
      _(last_response.status).must_equal 200

      result = JSON.parse(last_response.body)
      _(result['attributes']['username']).must_equal target.username
    end
  end

  describe 'Account Creation' do
    before do
      @account_data = DATA[:accounts][1]
    end

    it 'HAPPY: should be able to create new accounts' do
      post 'api/v1/accounts', @account_data.to_json, @req_header
      _(last_response.status).must_equal 201
      _(last_response.headers['Location'].size).must_be :>, 0

      created = JSON.parse(last_response.body)['data']['attributes']
      account = Tyto::Account.first

      _(created['id']).must_equal account.id
      _(created['username']).must_equal @account_data['username']
      _(created['email']).must_equal @account_data['email']
      _(account.password?(@account_data['password'])).must_equal true
      _(account.password?('not_really_the_password')).must_equal false
    end

    it 'BAD: should not create account with illegal attributes' do
      bad_data = @account_data.clone
      bad_data['created_at'] = '1900-01-01'
      post 'api/v1/accounts', bad_data.to_json, @req_header

      _(last_response.status).must_equal 400
      _(last_response.headers['Location']).must_be_nil
    end
  end

  describe 'Managing System Roles' do
    before do
      %w[admin creator member owner instructor staff student].each do |role_name|
        Tyto::Role.find_or_create(name: role_name)
      end

      @admin = Tyto::Account.create(DATA[:accounts][0])
      @admin.add_system_role(Tyto::Role.first(name: 'admin'))
      @target = Tyto::Account.create(DATA[:accounts][1])
    end

    it 'HAPPY: admin should promote a member to creator' do
      put(
        "/api/v1/accounts/#{@target.username}/system_roles/creator",
        { current_account_id: @admin.id }.to_json,
        @req_header
      )
      _(last_response.status).must_equal 201
      _(@target.reload.system_roles.map(&:name)).must_include 'creator'
    end

    it 'HAPPY: re-PUT of an already-assigned role is idempotent (200)' do
      @target.add_system_role(Tyto::Role.first(name: 'creator'))

      put(
        "/api/v1/accounts/#{@target.username}/system_roles/creator",
        { current_account_id: @admin.id }.to_json,
        @req_header
      )
      _(last_response.status).must_equal 200
      _(@target.reload.system_roles.count { |r| r.name == 'creator' }).must_equal 1
    end

    it 'HAPPY: admin should revoke a system role' do
      @target.add_system_role(Tyto::Role.first(name: 'creator'))

      delete(
        "/api/v1/accounts/#{@target.username}/system_roles/creator",
        { current_account_id: @admin.id }.to_json,
        @req_header
      )
      _(last_response.status).must_equal 200
      _(@target.reload.system_roles.map(&:name)).wont_include 'creator'
    end

    it 'BAD: non-admin (creator) should not be able to PUT a system role' do
      caller_account = Tyto::Account.create(DATA[:accounts][2])
      caller_account.add_system_role(Tyto::Role.first(name: 'creator'))

      put(
        "/api/v1/accounts/#{@target.username}/system_roles/creator",
        { current_account_id: caller_account.id }.to_json,
        @req_header
      )
      _(last_response.status).must_equal 403
      _(@target.reload.system_roles).must_be_empty
    end

    it 'BAD: non-admin (member) should not be able to DELETE a system role' do
      @target.add_system_role(Tyto::Role.first(name: 'creator'))
      caller_account = Tyto::Account.create(DATA[:accounts][2])

      delete(
        "/api/v1/accounts/#{@target.username}/system_roles/creator",
        { current_account_id: caller_account.id }.to_json,
        @req_header
      )
      _(last_response.status).must_equal 403
      _(@target.reload.system_roles.map(&:name)).must_include 'creator'
    end

    it 'BAD: course-only role rejected on PUT' do
      put(
        "/api/v1/accounts/#{@target.username}/system_roles/student",
        { current_account_id: @admin.id }.to_json,
        @req_header
      )
      _(last_response.status).must_equal 400
      _(@target.reload.system_roles).must_be_empty
    end

    it 'BAD: nonsense role rejected on PUT' do
      put(
        "/api/v1/accounts/#{@target.username}/system_roles/wizard",
        { current_account_id: @admin.id }.to_json,
        @req_header
      )
      _(last_response.status).must_equal 400
    end

    it 'BAD: unknown target username returns 404' do
      put(
        '/api/v1/accounts/nosuchuser/system_roles/creator',
        { current_account_id: @admin.id }.to_json,
        @req_header
      )
      _(last_response.status).must_equal 404
    end

    it 'BAD: DELETE of an unassigned role returns 404' do
      delete(
        "/api/v1/accounts/#{@target.username}/system_roles/creator",
        { current_account_id: @admin.id }.to_json,
        @req_header
      )
      _(last_response.status).must_equal 404
    end

    it 'SECURITY: missing current_account_id returns 401 on PUT' do
      put(
        "/api/v1/accounts/#{@target.username}/system_roles/creator",
        {}.to_json,
        @req_header
      )
      _(last_response.status).must_equal 401
    end

    it 'SECURITY: missing current_account_id returns 401 on DELETE' do
      delete(
        "/api/v1/accounts/#{@target.username}/system_roles/creator",
        {}.to_json,
        @req_header
      )
      _(last_response.status).must_equal 401
    end
  end
end
