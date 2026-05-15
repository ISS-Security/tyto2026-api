# frozen_string_literal: true

require 'base64'
require 'rbnacl'

require_relative 'securable'

module Tyto
  # Encrypt and Decrypt from Database
  class SecureDB
    extend Securable

    def self.setup(db_key, hash_key)
      setup_secret_key(db_key)
      setup_hash_key(hash_key)
    end

    def self.encrypt(plaintext)
      base_encrypt(plaintext)
    end

    def self.decrypt(ciphertext64)
      base_decrypt(ciphertext64)
    end

    # Keyed hash for deterministic lookup on encrypted columns
    def self.hash(plaintext)
      base_hash(plaintext)
    end
  end
end
