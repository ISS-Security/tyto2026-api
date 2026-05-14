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
end
