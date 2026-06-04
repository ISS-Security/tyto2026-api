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
    post 'api/v1/auth/authenticate', Tyto::SignedRequest.sign(creds).to_json, @req_header
    _(last_response.status).must_equal 200

    result = JSON.parse last_response.body
    _(result['type']).must_equal 'authenticated_account'

    account = result['attributes']['account']
    _(account['type']).must_equal 'account'
    _(account['attributes']['username']).must_equal @account_data['username']
    _(account['attributes']['email']).must_equal @account_data['email']
    _(account['include']['enrollments']).must_be_kind_of Array
    _(account['include']['system_roles']).must_be_kind_of Array

    _(result['attributes']['auth_token']).must_be_kind_of String
    _(result['attributes']['auth_token']).wont_be_empty
  end

  it 'SECURITY: returned auth_token decrypts to an account payload' do
    creds = { username: @account_data['username'], password: @account_data['password'] }
    post 'api/v1/auth/authenticate', Tyto::SignedRequest.sign(creds).to_json, @req_header
    token = JSON.parse(last_response.body)['attributes']['auth_token']

    payload = Tyto::AuthToken.load(token).payload
    _(payload['type']).must_equal 'account'
    _(payload['attributes']['username']).must_equal @account_data['username']
  end

  it 'BAD: should reject invalid password' do
    bad_creds = { username: @account_data['username'], password: 'not_the_password' }
    post 'api/v1/auth/authenticate', Tyto::SignedRequest.sign(bad_creds).to_json, @req_header
    _(last_response.status).must_equal 401

    result = JSON.parse last_response.body
    _(result['message']).wont_be_nil
    _(result['attributes']).must_be_nil
  end

  it 'BAD: should reject unknown username' do
    creds = { username: 'nosuchuser', password: 'anything' }
    post 'api/v1/auth/authenticate', Tyto::SignedRequest.sign(creds).to_json, @req_header
    _(last_response.status).must_equal 401
  end

  it 'BAD SIGNED_REQUEST: should not accept unsigned authentication requests' do
    creds = { username: @account_data['username'], password: @account_data['password'] }
    post 'api/v1/auth/authenticate', creds.to_json, @req_header
    _(last_response.status).must_equal 403
  end

  describe 'Registration verification' do
    before do
      require 'webmock/minitest'
      @mail_url = ENV.fetch('RESEND_API_URL')
      @registration = {
        email: 'someone-new@example.com',
        username: 'someone_new',
        verification_url: 'https://app.example.com/auth/register/abc'
      }
    end

    after { WebMock.reset! }

    it 'HAPPY: returns 202 and triggers a Resend POST' do
      stub = stub_request(:post, @mail_url).to_return(status: 200)
      post 'api/v1/auth/register', Tyto::SignedRequest.sign(@registration).to_json, @req_header
      _(last_response.status).must_equal 202
      assert_requested(stub)
    end

    it 'BAD: returns 400 when email is already taken' do
      stub_request(:post, @mail_url).to_return(status: 200)
      registration = @registration.merge(email: @account_data['email'])
      post 'api/v1/auth/register', Tyto::SignedRequest.sign(registration).to_json, @req_header
      _(last_response.status).must_equal 400
    end

    it 'BAD: returns 500 when Resend rejects' do
      stub_request(:post, @mail_url).to_return(status: 503)
      post 'api/v1/auth/register', Tyto::SignedRequest.sign(@registration).to_json, @req_header
      _(last_response.status).must_equal 500
    end
  end

  describe 'SSO Authentication' do
    before do
      require 'webmock/minitest'
      Tyto::Role.find_or_create(name: 'member')
      stub_request(:get, Tyto::GoogleIdToken::JWKS_URI).to_return(
        body: SsoTestKeys.jwks.to_json, status: 200,
        headers: { 'content-type' => 'application/json' }
      )
    end

    after { WebMock.reset! }

    it 'HAPPY: a valid id_token returns an authorized account + FULL-scope token' do
      post 'api/v1/auth/sso',
        Tyto::SignedRequest.sign({ id_token: SsoTestKeys.mint_id_token }).to_json, @req_header

      _(last_response.status).must_equal 200
      data = JSON.parse(last_response.body)['data']
      _(data['type']).must_equal 'authorized_account'

      account = data['attributes']['account']['attributes']
      _(account['email']).must_equal 'sso-user@example.com'
      _(account['avatar']).must_equal SsoTestKeys.default_claims['picture']
      _(account['id']).must_be_nil # internal id stays out of the plaintext envelope

      token = data['attributes']['auth_token']
      _(token).must_be_kind_of String
      _(Tyto::AuthToken.load(token).scope).must_equal Tyto::AuthScope::FULL
    end

    it 'HAPPY: a repeat login with the same identity reuses the one account' do
      2.times do
        post 'api/v1/auth/sso',
          Tyto::SignedRequest.sign({ id_token: SsoTestKeys.mint_id_token }).to_json, @req_header
      end
      _(last_response.status).must_equal 200
      _(Tyto::SsoIdentity.where(provider: 'google').count).must_equal 1
    end

    it 'BAD: a malformed token is rejected with 401' do
      post 'api/v1/auth/sso', Tyto::SignedRequest.sign({ id_token: 'not-a-jwt' }).to_json, @req_header
      _(last_response.status).must_equal 401
    end

    it 'BAD: a token with the wrong audience is rejected with 401' do
      post 'api/v1/auth/sso',
        Tyto::SignedRequest.sign(
          { id_token: SsoTestKeys.mint_id_token('aud' => 'wrong-client') }
        ).to_json, @req_header
      _(last_response.status).must_equal 401
    end

    it 'BAD: a missing id_token is rejected with 400' do
      post 'api/v1/auth/sso', Tyto::SignedRequest.sign({}).to_json, @req_header
      _(last_response.status).must_equal 400
    end
  end
end
