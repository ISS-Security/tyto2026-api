# frozen_string_literal: true

require 'http'

module Tyto
  # Sends a verification email to a prospective account-holder so that
  # only someone who can read the inbox can finish account creation.
  # Wraps Resend's POST /emails endpoint with Bearer auth.
  class VerifyRegistration
    class InvalidRegistration < StandardError; end
    class EmailProviderError < StandardError; end

    def initialize(registration)
      @registration = registration
    end

    def call
      raise InvalidRegistration, 'Email already registered' unless email_available?
      raise InvalidRegistration, 'Username already taken' unless username_available?

      send_email
      @registration
    end

    private

    def email_available?
      Account.first(email_hash: SecureDB.hash(@registration[:email])).nil?
    end

    def username_available?
      Account.first(username: @registration[:username]).nil?
    end

    def send_email
      response = HTTP
                 .auth("Bearer #{api_key}")
                 .post(mail_url, json: mail_json)
      return if response.status < 300

      Api.logger.error("Resend error #{response.status}: #{response.body}")
      raise EmailProviderError, 'Email provider rejected the request'
    end

    def api_key = ENV.fetch('RESEND_API_KEY')
    def mail_url = ENV.fetch('RESEND_API_URL')
    def from_email = ENV.fetch('RESEND_FROM_EMAIL')
    def from_name = ENV.fetch('RESEND_FROM_NAME', 'Tyto')

    def mail_json
      {
        from: "#{from_name} <#{from_email}>",
        to: [@registration[:email]],
        subject: 'Tyto Registration Verification',
        html: html_body
      }
    end

    def html_body
      <<~HTML
        <h2>Welcome to Tyto, #{@registration[:username]}!</h2>
        <p>Click the link below to finish creating your account:</p>
        <p><a href="#{@registration[:verification_url]}">Verify your registration</a></p>
        <p>If you didn't request this, you can safely ignore this email.</p>
      HTML
    end
  end
end
