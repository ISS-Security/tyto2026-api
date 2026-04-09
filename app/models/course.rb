# frozen_string_literal: true

require 'json'
require 'base64'
require 'rbnacl'

module Tyto
  STORE_DIR = 'db/local'

  # Holds a full course record
  class Course
    # Create a new course by passing in hash of attributes
    def initialize(new_course)
      @id          = new_course['id'] || new_id
      @name        = new_course['name']
      @description = new_course['description']
    end

    attr_reader :id, :name, :description

    def to_json(options = {})
      JSON(
        {
          type: 'course',
          id:,
          name:,
          description:
        },
        options
      )
    end

    # File store must be setup once when application runs
    def self.setup
      FileUtils.mkdir_p(Tyto::STORE_DIR)
    end

    # Stores course in file store
    def save
      File.write("#{Tyto::STORE_DIR}/#{id}.txt", to_json)
    end

    # Query method to find one course
    def self.find(find_id)
      course_file = File.read("#{Tyto::STORE_DIR}/#{find_id}.txt")
      Course.new JSON.parse(course_file)
    end

    # Query method to retrieve index of all courses
    def self.all
      Dir.glob("#{Tyto::STORE_DIR}/*.txt").map do |file|
        file.match(%r{#{Regexp.quote(Tyto::STORE_DIR)}/(.*)\.txt})[1]
      end
    end

    private

    def new_id
      timestamp = Time.now.to_f.to_s
      Base64.urlsafe_encode64(RbNaCl::Hash.sha256(timestamp))[0..9]
    end
  end
end
