# frozen_string_literal: true

require 'roda'
require_relative 'app'

module Tyto
  # Web controller for Tyto API
  class Api < Roda
    route('auth') do |routing|
      # All requests in this route require signed requests
      begin
        @request_data = HttpRequest.new(routing).signed_body_data
      rescue SignedRequest::VerificationError
        routing.halt 403, { message: 'Must sign request' }.to_json
      end

      routing.is 'authenticate' do
        # POST api/v1/auth/authenticate
        routing.post do
          AuthenticateAccount.call(@request_data).to_json
        rescue AuthenticateAccount::UnauthorizedError
          Api.logger.warn('Authentication failed: invalid credentials')
          routing.halt 401, { message: 'Invalid credentials' }.to_json
        end
      end

      routing.is 'register' do
        # POST api/v1/auth/register
        routing.post do
          VerifyRegistration.new(@request_data).call
          response.status = 202
          { message: 'Verification email sent' }.to_json
        rescue VerifyRegistration::InvalidRegistration => e
          routing.halt 400, { message: e.message }.to_json
        rescue VerifyRegistration::EmailProviderError => e
          Api.logger.error("Registration email failed: #{e.message}")
          routing.halt 500, { message: 'Could not send verification email' }.to_json
        rescue StandardError => e
          Api.logger.error("UNKNOWN ERROR: #{e.message}")
          routing.halt 500, { message: 'Unknown server error' }.to_json
        end
      end

      routing.is 'sso' do
        # POST api/v1/auth/sso  -- body: { id_token: <Google-signed JWT> }
        routing.post do
          id_token = @request_data[:id_token]
          routing.halt(400, { message: 'Missing id_token' }.to_json) if id_token.to_s.empty?

          { data: AuthenticateSso.call(id_token) }.to_json
        rescue OidcVerifier::VerificationError => e
          Api.logger.warn("SSO verification failed: #{e.message}")
          routing.halt 401, { message: 'Invalid SSO credentials' }.to_json
        rescue FindOrCreateSsoAccount::EmailConflictError
          routing.halt 409, { message: 'Email already registered to another account' }.to_json
        rescue StandardError => e
          Api.logger.error("SSO ERROR: #{e.message}")
          routing.halt 400, { message: 'SSO authentication failed' }.to_json
        end
      end
    end
  end
end
