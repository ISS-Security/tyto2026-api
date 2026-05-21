# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Tyto::AuthenticateAccount service' do
  before do
    wipe_database
    @account_data = DATA[:accounts][1]
    @account = Tyto::Account.create(@account_data)
  end

  it 'HAPPY: returns an authenticated_account envelope with embedded account and token' do
    creds = { username: @account_data['username'], password: @account_data['password'] }
    result = Tyto::AuthenticateAccount.call(creds)

    _(result[:type]).must_equal 'authenticated_account'
    _(result[:attributes][:account]).must_be_kind_of Hash
    _(result[:attributes][:account]['type']).must_equal 'account'
    _(result[:attributes][:account]['attributes']['username']).must_equal @account_data['username']
    _(result[:attributes][:auth_token]).must_be_kind_of String
    _(result[:attributes][:auth_token]).wont_be_empty
  end

  it 'SECURITY: token round-trips back to the account envelope' do
    creds = { username: @account_data['username'], password: @account_data['password'] }
    result = Tyto::AuthenticateAccount.call(creds)

    token = result[:attributes][:auth_token]
    payload = Tyto::AuthToken.load(token).payload
    _(payload['type']).must_equal 'account'
    _(payload['attributes']['username']).must_equal @account_data['username']
  end

  it 'BAD: raises UnauthorizedError on wrong password' do
    creds = { username: @account_data['username'], password: 'wrong' }
    _ { Tyto::AuthenticateAccount.call(creds) }
      .must_raise Tyto::AuthenticateAccount::UnauthorizedError
  end

  it 'BAD: raises UnauthorizedError on unknown username' do
    creds = { username: 'nosuchuser', password: 'anything' }
    _ { Tyto::AuthenticateAccount.call(creds) }
      .must_raise Tyto::AuthenticateAccount::UnauthorizedError
  end

  describe 'SECURITY: response carries actor-scoped capabilities' do
    before do
      %w[admin creator member].each { |n| Tyto::Role.find_or_create(name: n) }
    end

    def call_authenticate
      creds = { username: @account_data['username'], password: @account_data['password'] }
      JSON.parse(JSON.dump(Tyto::AuthenticateAccount.call(creds)))
    end

    it 'HAPPY: envelope account block carries a capabilities hash' do
      result = call_authenticate
      caps = result['attributes']['account']['capabilities']

      _(caps).must_be_kind_of Hash
      _(caps.keys.sort).must_equal %w[can_create_course can_manage_system_roles is_admin]
    end

    it 'HAPPY: member account gets all capabilities false' do
      @account.add_system_role(Tyto::Role.first(name: 'member'))
      caps = call_authenticate['attributes']['account']['capabilities']

      _(caps['is_admin']).must_equal false
      _(caps['can_create_course']).must_equal false
      _(caps['can_manage_system_roles']).must_equal false
    end

    it 'HAPPY: admin account gets is_admin + can_create_course + can_manage_system_roles true' do
      @account.add_system_role(Tyto::Role.first(name: 'admin'))
      caps = call_authenticate['attributes']['account']['capabilities']

      _(caps['is_admin']).must_equal true
      _(caps['can_create_course']).must_equal true
      _(caps['can_manage_system_roles']).must_equal true
    end
  end
end
