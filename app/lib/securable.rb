# frozen_string_literal: true

require 'base64'
require 'rbnacl'

module Tyto
  # Shared SimpleBox primitives for libraries that encrypt/decrypt at rest
  # or over the wire (SecureDB, AuthToken).
  module Securable
    class NoKeyError < StandardError; end

    def generate_key
      key = RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes)
      Base64.strict_encode64(key)
    end

    def setup(base_key)
      raise NoKeyError unless base_key

      @key = Base64.strict_decode64(base_key)
    end

    def key
      @key
    end

    def base_encrypt(plaintext)
      return nil unless plaintext

      simple_box = RbNaCl::SimpleBox.from_secret_key(@key)
      ciphertext = simple_box.encrypt(plaintext)
      Base64.strict_encode64(ciphertext)
    end

    def base_decrypt(ciphertext64)
      return nil unless ciphertext64

      ciphertext = Base64.strict_decode64(ciphertext64)
      simple_box = RbNaCl::SimpleBox.from_secret_key(@key)
      simple_box.decrypt(ciphertext).force_encoding(Encoding::UTF_8)
    end
  end
end
