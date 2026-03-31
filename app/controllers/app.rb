# frozen_string_literal: true

require 'roda'
require 'json'
require 'logger'

require_relative '../models/course'

module Tyto
  # Web controller for Tyto API
  class Api < Roda
    plugin :environments
    plugin :halt
    plugin :common_logger, $stderr

    configure do
      Course.setup
    end

    route do |routing| # rubocop:disable Metrics/BlockLength
      response['Content-Type'] = 'application/json'

      routing.root do
        response.status = 200
        { message: 'TytoAPI up at /api/v1' }.to_json
      end

      routing.on 'api' do
        routing.on 'v1' do
          routing.on 'courses' do
            # GET api/v1/courses/[id]
            routing.get String do |id|
              response.status = 200
              Course.find(id).to_json
            rescue StandardError
              routing.halt 404, { message: 'Course not found' }.to_json
            end

            # GET api/v1/courses
            routing.get do
              response.status = 200
              output = { course_ids: Course.all }
              JSON.pretty_generate(output)
            end

            # POST api/v1/courses
            routing.post do
              new_data = JSON.parse(routing.body.read)
              new_course = Course.new(new_data)

              if new_course.save
                response.status = 201
                { message: 'Course saved', id: new_course.id }.to_json
              else
                routing.halt 400, { message: 'Could not save course' }.to_json
              end
            end
          end
        end
      end
    end
  end
end
