# frozen_string_literal: true

require 'base64'
require 'rbnacl'

require_relative 'securable'

module Tyto
  # Encrypt and Decrypt from Database
  class SecureDB
    extend Securable

    class NoHashKeyError < StandardError; end

    def self.setup(db_key, hash_key)
      super(db_key)
      raise NoHashKeyError unless hash_key

      @hash_key = Base64.strict_decode64(hash_key)
    end

    def self.encrypt(plaintext)
      base_encrypt(plaintext)
    end

    def self.decrypt(ciphertext64)
      base_decrypt(ciphertext64)
    end

    # Keyed hash for deterministic lookup on encrypted columns
    def self.hash(plaintext)
      return nil unless plaintext

      digest = RbNaCl::HMAC::SHA256.auth(@hash_key, plaintext)
      Base64.strict_encode64(digest)
    end
  end
end
