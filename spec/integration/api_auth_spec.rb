# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Authentication' do
  include Rack::Test::Methods

  before do
    wipe_database
    @req_header = { 'CONTENT_TYPE' => 'application/json' }
    @account_data = DATA[:accounts][1]
    @account = Tyto::Account.create(@account_data)
  end

  it 'HAPPY: should authenticate valid credentials' do
    creds = { username: @account_data['username'], password: @account_data['password'] }
    post 'api/v1/auth/authenticate', creds.to_json, @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['type']).must_equal 'account'
    _(result['attributes']['id']).must_equal @account.id
    _(result['attributes']['username']).must_equal @account_data['username']
    _(result['attributes']['email']).must_equal @account_data['email']
    _(result['include']['enrollments']).must_be_kind_of Array
    _(result['include']['system_roles']).must_be_kind_of Array
  end

  it 'BAD: should reject invalid password and log to stdout (no stderr)' do
    creds = { username: @account_data['username'], password: 'not_the_password' }
    assert_output(/invalid/i, '') do
      post 'api/v1/auth/authenticate', creds.to_json, @req_header
    end
    _(last_response.status).must_equal 403

    result = JSON.parse last_response.body
    _(result['message']).wont_be_nil
    _(result['attributes']).must_be_nil
  end

  it 'BAD: should reject unknown username' do
    creds = { username: 'nosuchuser', password: 'anything' }
    assert_output(/invalid/i, '') do
      post 'api/v1/auth/authenticate', creds.to_json, @req_header
    end
    _(last_response.status).must_equal 403
  end
end
