# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test FindOrCreateSsoAccount service' do
  before do
    wipe_database
    Tyto::Role.find_or_create(name: 'member')
  end

  def google_claims(overrides = {})
    {
      provider: 'google',
      external_id: 'google-sub-123',
      email: 'newuser@example.com',
      email_verified: true,
      name: 'New User',
      avatar: 'https://example.com/p.jpg'
    }.merge(overrides)
  end

  it 'HAPPY: creates a member account + identity for a first-time login' do
    account = Tyto::FindOrCreateSsoAccount.call(**google_claims)

    _(account).must_be_kind_of Tyto::Account
    _(account.system_roles.map(&:name)).must_include 'member'
    _(account.email).must_equal 'newuser@example.com'
    _(account.avatar).must_equal 'https://example.com/p.jpg'

    identity = Tyto::SsoIdentity.first(provider: 'google', external_id: 'google-sub-123')
    _(identity).wont_be_nil
    _(identity.account_id).must_equal account.id
  end

  it 'HAPPY: a repeat login returns the same account (idempotent identity)' do
    first = Tyto::FindOrCreateSsoAccount.call(**google_claims)
    second = Tyto::FindOrCreateSsoAccount.call(**google_claims)

    _(second.id).must_equal first.id
    _(Tyto::SsoIdentity.where(provider: 'google', external_id: 'google-sub-123').count).must_equal 1
    _(Tyto::Account.count).must_equal 1
  end

  it 'LINK: links a verified-email match to the existing account' do
    existing = Tyto::Account.create(
      username: 'existing', email: 'newuser@example.com', password: 'PangolinReef42!'
    )

    account = Tyto::FindOrCreateSsoAccount.call(**google_claims)

    _(account.id).must_equal existing.id
    _(Tyto::Account.count).must_equal 1
    _(Tyto::SsoIdentity.first(provider: 'google', external_id: 'google-sub-123').account_id)
      .must_equal existing.id
  end

  it 'SECURITY: an unverified email matching an existing account neither links nor duplicates' do
    Tyto::Account.create(
      username: 'existing', email: 'newuser@example.com', password: 'PangolinReef42!'
    )

    _ { Tyto::FindOrCreateSsoAccount.call(**google_claims(email_verified: false)) }
      .must_raise Tyto::FindOrCreateSsoAccount::EmailConflictError

    _(Tyto::Account.count).must_equal 1 # no takeover, no duplicate
    _(Tyto::SsoIdentity.count).must_equal 0
  end

  it 'creates a fresh account for an unverified email that collides with nothing' do
    account = Tyto::FindOrCreateSsoAccount.call(
      **google_claims(email_verified: false, email: 'fresh@example.com', external_id: 'sub-x')
    )

    _(account).must_be_kind_of Tyto::Account
    _(account.email).must_equal 'fresh@example.com'
    _(Tyto::Account.count).must_equal 1
  end

  it 'derives username from the email local-part, suffixing @provider on collision' do
    Tyto::Account.create(
      username: 'newuser', email: 'someone@else.com', password: 'PangolinReef42!'
    )

    account = Tyto::FindOrCreateSsoAccount.call(**google_claims)

    _(account.username).must_equal 'newuser@google'
  end
end
