# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Password Digestion' do
  # Non-ASCII characters exercise the `force_encoding(UTF_8)` guarantee
  # that SecureDB.decrypt has held since 2-db-hardening.
  let(:password) { 'secret password of 雷松亞 stored in db' }

  it 'SECURITY: create password digests safely, hiding raw password' do
    digest = Tyto::Password.digest(password)

    _(digest.to_s.match?(password)).must_equal false
  end

  it 'SECURITY: successfully checks correct password from stored digest' do
    digest_s = Tyto::Password.digest(password).to_s

    digest = Tyto::Password.from_digest(digest_s)
    _(digest.correct?(password)).must_equal true
  end

  it 'SECURITY: successfully detects incorrect password from stored digest' do
    other_password = 'ediblesofunusualsizecolorandtexture'
    digest_s = Tyto::Password.digest(password).to_s

    digest = Tyto::Password.from_digest(digest_s)
    _(digest.correct?(other_password)).must_equal false
  end
end
