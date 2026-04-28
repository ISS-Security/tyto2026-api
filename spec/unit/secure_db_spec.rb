# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Tyto::SecureDB Class' do
  it 'SECURITY: should encrypt text' do
    test_data = 'test data'
    text_sec = Tyto::SecureDB.encrypt(test_data)
    _(text_sec).wont_equal test_data
  end

  it 'SECURITY: should decrypt encrypted ASCII' do
    test_data = "test data ~ 1 & \n"
    text_sec = Tyto::SecureDB.encrypt(test_data)
    test_decrypted = Tyto::SecureDB.decrypt(text_sec)
    _(test_decrypted).must_equal test_data
  end

  it 'SECURITY: should decrypt non-ASCII characters' do
    test_data = '我的名字是雷松亞'
    text_sec = Tyto::SecureDB.encrypt(test_data)
    test_decrypted = Tyto::SecureDB.decrypt(text_sec)
    _(test_decrypted).must_equal test_data
  end

  it 'SECURITY: should produce deterministic keyed hashes for same input' do
    test_data = 'alice@example.com'
    first_hash = Tyto::SecureDB.hash(test_data)
    second_hash = Tyto::SecureDB.hash(test_data)
    _(first_hash).must_equal second_hash
    _(first_hash).wont_equal test_data
  end

  it 'SECURITY: should produce different keyed hashes for different inputs' do
    alice_hash = Tyto::SecureDB.hash('alice@example.com')
    bob_hash = Tyto::SecureDB.hash('bob@example.com')
    _(alice_hash).wont_equal bob_hash
  end
end
