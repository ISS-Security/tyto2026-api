# frozen_string_literal: true

require 'roda'
require 'json'
require 'logger'

module Tyto
  # Web controller for Tyto API
  class Api < Roda
    plugin :halt

    route do |routing|
      response['Content-Type'] = 'application/json'

      routing.root do
        { message: 'TytoAPI up at /api/v1' }.to_json
      end

      @api_root = 'api/v1'
      routing.on @api_root do
        routing.on 'courses' do
          @course_route = "#{@api_root}/courses"

          routing.on String do |course_id|
            routing.on 'events' do
              @event_route = "#{@api_root}/courses/#{course_id}/events"

              # GET api/v1/courses/[course_id]/events/[event_id]
              routing.get String do |event_id|
                event = Event.where(course_id:, id: event_id).first
                event ? event.to_json : raise('Event not found')
              rescue StandardError => e
                routing.halt 404, { message: e.message }.to_json
              end

              # GET api/v1/courses/[course_id]/events
              routing.get do
                output = { data: Course.first(id: course_id).events }
                JSON.pretty_generate(output)
              rescue StandardError
                routing.halt 404, { message: 'Could not find events' }.to_json
              end

              # POST api/v1/courses/[course_id]/events
              routing.post do
                new_data = JSON.parse(routing.body.read)
                course = Course.first(id: course_id)
                new_event = course.add_event(new_data)

                if new_event
                  response.status = 201
                  response['Location'] = "#{@event_route}/#{new_event.id}"
                  { message: 'Event saved', data: new_event }.to_json
                else
                  routing.halt 400, 'Could not save event'
                end
              rescue StandardError
                routing.halt 500, { message: 'Database error' }.to_json
              end
            end

            routing.on 'locations' do
              @location_route = "#{@api_root}/courses/#{course_id}/locations"

              # GET api/v1/courses/[course_id]/locations/[location_id]
              routing.get String do |location_id|
                loc = Location.where(course_id:, id: location_id).first
                loc ? loc.to_json : raise('Location not found')
              rescue StandardError => e
                routing.halt 404, { message: e.message }.to_json
              end

              # GET api/v1/courses/[course_id]/locations
              routing.get do
                output = { data: Course.first(id: course_id).locations }
                JSON.pretty_generate(output)
              rescue StandardError
                routing.halt 404, { message: 'Could not find locations' }.to_json
              end

              # POST api/v1/courses/[course_id]/locations
              routing.post do
                new_data = JSON.parse(routing.body.read)
                course = Course.first(id: course_id)
                new_loc = course.add_location(new_data)

                if new_loc
                  response.status = 201
                  response['Location'] = "#{@location_route}/#{new_loc.id}"
                  { message: 'Location saved', data: new_loc }.to_json
                else
                  routing.halt 400, 'Could not save location'
                end
              rescue StandardError
                routing.halt 500, { message: 'Database error' }.to_json
              end
            end

            # GET api/v1/courses/[course_id]
            routing.get do
              course = Course.first(id: course_id)
              course ? course.to_json : raise('Course not found')
            rescue StandardError => e
              routing.halt 404, { message: e.message }.to_json
            end
          end

          # GET api/v1/courses
          routing.get do
            output = { data: Course.all }
            JSON.pretty_generate(output)
          rescue StandardError
            routing.halt 404, { message: 'Could not find courses' }.to_json
          end

          # POST api/v1/courses
          routing.post do
            new_data = JSON.parse(routing.body.read)
            new_course = Course.new(new_data)
            raise('Could not save course') unless new_course.save_changes

            response.status = 201
            response['Location'] = "#{@course_route}/#{new_course.id}"
            { message: 'Course saved', data: new_course }.to_json
          rescue StandardError => e
            routing.halt 400, { message: e.message }.to_json
          end
        end
      end
    end
  end
end
