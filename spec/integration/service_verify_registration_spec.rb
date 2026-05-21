# frozen_string_literal: true

require_relative '../spec_helper'
require 'webmock/minitest'

describe 'Test Tyto::VerifyRegistration service' do
  before do
    wipe_database
    @mail_url = ENV.fetch('RESEND_API_URL')
    @registration = {
      email: 'newperson@example.com',
      username: 'newperson',
      verification_url: 'https://app.example.com/auth/register/some-token'
    }
  end

  after { WebMock.reset! }

  it 'HAPPY: POSTs the Resend envelope and returns the registration' do
    stub = stub_request(:post, @mail_url)
           .with(headers: { 'Authorization' => 'Bearer stub-key-not-used-in-tests' })
           .to_return(status: 200, body: { id: 'fake-email-id' }.to_json)

    result = Tyto::VerifyRegistration.new(@registration).call

    _(result[:email]).must_equal @registration[:email]
    assert_requested(stub)
  end

  it 'SECURITY: request body uses Resend lowercase envelope with from/to/subject/html' do
    stub_request(:post, @mail_url).to_return(status: 200)

    Tyto::VerifyRegistration.new(@registration).call

    assert_requested(:post, @mail_url) do |req|
      body = JSON.parse(req.body)
      body['from'].include?('noreply@example.com') &&
        body['to'] == [@registration[:email]] &&
        body['subject'].include?('Verification') &&
        body['html'].include?(@registration[:verification_url])
    end
  end

  it 'SAD: raises InvalidRegistration when email already registered' do
    Tyto::Account.create(DATA[:accounts][1])
    @registration[:email] = DATA[:accounts][1]['email']

    _ { Tyto::VerifyRegistration.new(@registration).call }
      .must_raise Tyto::VerifyRegistration::InvalidRegistration
  end

  it 'SAD: raises InvalidRegistration when username already taken' do
    Tyto::Account.create(DATA[:accounts][1])
    @registration[:username] = DATA[:accounts][1]['username']

    _ { Tyto::VerifyRegistration.new(@registration).call }
      .must_raise Tyto::VerifyRegistration::InvalidRegistration
  end

  it 'SAD: raises EmailProviderError on 4xx response from Resend' do
    stub_request(:post, @mail_url)
      .to_return(status: 400, body: { message: 'bad' }.to_json)

    _ { Tyto::VerifyRegistration.new(@registration).call }
      .must_raise Tyto::VerifyRegistration::EmailProviderError
  end

  it 'SAD: raises EmailProviderError on 5xx response from Resend' do
    stub_request(:post, @mail_url).to_return(status: 503, body: 'unavailable')

    _ { Tyto::VerifyRegistration.new(@registration).call }
      .must_raise Tyto::VerifyRegistration::EmailProviderError
  end
end
