# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Secret credentials not exposed' do
  it 'should not find database url' do
    _(Tyto::Api.config.DATABASE_URL).must_be_nil
  end

  it 'should not find database key' do
    _(Tyto::Api.config.DB_KEY).must_be_nil
  end

  it 'should not find hash lookup key' do
    _(Tyto::Api.config.HASH_KEY).must_be_nil
  end
end
