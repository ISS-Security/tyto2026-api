# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/rg'
require 'rack/test'
require 'yaml'

require_relative '../app/controllers/app'
require_relative '../app/models/course'

def app
  Tyto::Api
end

DATA = YAML.safe_load_file('db/seeds/course_seeds.yml')

describe 'Test Tyto Web API' do
  include Rack::Test::Methods

  before do
    # Wipe database before each test
    Dir.glob("#{Tyto::STORE_DIR}/*.txt").each { |filename| FileUtils.rm(filename) }
  end

  it 'should find the root route' do
    get '/'
    _(last_response.status).must_equal 200
  end

  describe 'Handle courses' do
    it 'HAPPY: should be able to get list of all courses' do
      Tyto::Course.new(DATA[0]).save
      Tyto::Course.new(DATA[1]).save

      get 'api/v1/courses'
      result = JSON.parse last_response.body
      _(result['course_ids'].uniq.count).must_equal 2
    end

    it 'HAPPY: should be able to get details of a single course' do
      Tyto::Course.new(DATA[1]).save
      id = Dir.glob("#{Tyto::STORE_DIR}/*.txt").first.split(%r{[/.]})[-2]

      get "/api/v1/courses/#{id}"
      result = JSON.parse last_response.body

      _(last_response.status).must_equal 200
      _(result['id']).must_equal id
    end

    it 'SAD: should return error if unknown course requested' do
      get '/api/v1/courses/foobar'

      _(last_response.status).must_equal 404
    end

    it 'HAPPY: should be able to create new courses' do
      req_header = { 'CONTENT_TYPE' => 'application/json' }
      post 'api/v1/courses', DATA[1].to_json, req_header

      _(last_response.status).must_equal 201
    end
  end
end
