# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Tyto::SignedRequest' do
  let(:keypair) { Tyto::SignedRequest.generate_keypair }
  let(:payload) { { username: 'chen.hsinyi', password: 'mypa$$word' } }

  # These tests re-run .setup with their own keypairs; snapshot and restore
  # the environment-configured keys so integration specs running later in
  # the same process keep signing with the test keypair from secrets.yml.
  before do
    @config_keys = %i[@verify_key @signing_key]
                   .map { |var| Tyto::SignedRequest.instance_variable_get(var) }
  end

  after do
    Tyto::SignedRequest.instance_variable_set(:@verify_key, @config_keys[0])
    Tyto::SignedRequest.instance_variable_set(:@signing_key, @config_keys[1])
  end

  it 'SECURITY: should generate a keypair of Base64-encoded 32-byte keys' do
    _(Base64.strict_decode64(keypair[:signing_key]).bytesize).must_equal 32
    _(Base64.strict_decode64(keypair[:verify_key]).bytesize).must_equal 32
  end

  it 'SECURITY: should round-trip a signed message via sign then parse' do
    Tyto::SignedRequest.setup(keypair[:verify_key], keypair[:signing_key])

    signed = Tyto::SignedRequest.sign(payload)
    _(signed[:data]).must_equal payload
    _(signed[:signature]).must_be_kind_of String

    _(Tyto::SignedRequest.parse(signed)).must_equal payload
  end

  it 'SECURITY: should raise VerificationError on a forged signature' do
    Tyto::SignedRequest.setup(keypair[:verify_key], keypair[:signing_key])
    signed = Tyto::SignedRequest.sign(payload)

    forger = Tyto::SignedRequest.generate_keypair
    forged_signature = Base64.strict_encode64(
      RbNaCl::SigningKey.new(Base64.strict_decode64(forger[:signing_key]))
                        .sign(payload.to_json)
    )

    _ { Tyto::SignedRequest.parse(data: payload, signature: forged_signature) }
      .must_raise Tyto::SignedRequest::VerificationError

    tampered = { data: { username: 'attacker' }, signature: signed[:signature] }
    _ { Tyto::SignedRequest.parse(tampered) }
      .must_raise Tyto::SignedRequest::VerificationError
  end

  it 'SECURITY: should raise VerificationError on missing signature' do
    Tyto::SignedRequest.setup(keypair[:verify_key])

    _ { Tyto::SignedRequest.parse(payload) }
      .must_raise Tyto::SignedRequest::VerificationError
  end

  it 'SECURITY: should raise KeypairError when setup with bad keys' do
    _ { Tyto::SignedRequest.setup('not-base64!!') }
      .must_raise Tyto::SignedRequest::KeypairError
  end

  it 'SECURITY: should refuse to sign when setup ran verify-only' do
    Tyto::SignedRequest.setup(keypair[:verify_key])

    _ { Tyto::SignedRequest.sign(payload) }
      .must_raise Tyto::SignedRequest::KeypairError
  end
end
