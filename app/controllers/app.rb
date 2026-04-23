# frozen_string_literal: true

require 'roda'
require 'json'
require 'logger'

module Tyto
  # Web controller for Tyto API
  class Api < Roda # rubocop:disable Metrics/ClassLength
    plugin :halt
    plugin :all_verbs

    route do |routing|
      response['Content-Type'] = 'application/json'

      routing.root do
        { message: 'TytoAPI up at /api/v1' }.to_json
      end

      @api_root = 'api/v1'
      routing.on @api_root do
        routing.on 'accounts' do
          @account_route = "#{@api_root}/accounts"

          routing.on String do |username|
            # GET api/v1/accounts/[username]
            routing.get do
              account = Account.first(username:)
              account ? account.to_json : raise('Account not found')
            rescue StandardError => e
              routing.halt 404, { message: e.message }.to_json
            end
          end

          # POST api/v1/accounts
          routing.post do
            new_data = JSON.parse(routing.body.read)
            new_account = Account.new(new_data)
            raise('Could not save account') unless new_account.save_changes

            response.status = 201
            response['Location'] = "#{@account_route}/#{new_account.id}"
            { message: 'Account saved', data: new_account }.to_json
          rescue Sequel::MassAssignmentRestriction
            Api.logger.warn "MASS-ASSIGNMENT: #{new_data.keys}"
            routing.halt 400, { message: 'Illegal Attributes' }.to_json
          rescue StandardError => e
            Api.logger.error "UNKNOWN ERROR: #{e.message}"
            routing.halt 500, { message: 'Unknown server error' }.to_json
          end
        end

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
                new_event = CreateEventForCourse.call(
                  course_id:, event_data: new_data
                )
                raise 'Could not save event' unless new_event

                response.status = 201
                response['Location'] = "#{@event_route}/#{new_event.id}"
                { message: 'Event saved', data: new_event }.to_json
              rescue Sequel::MassAssignmentRestriction
                Api.logger.warn "MASS-ASSIGNMENT: #{new_data.keys}"
                routing.halt 400, { message: 'Illegal Attributes' }.to_json
              rescue StandardError => e
                Api.logger.error "UNKNOWN ERROR: #{e.message}"
                routing.halt 500, { message: 'Unknown server error' }.to_json
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
                new_loc = CreateLocationForCourse.call(
                  course_id:, location_data: new_data
                )
                raise 'Could not save location' unless new_loc

                response.status = 201
                response['Location'] = "#{@location_route}/#{new_loc.id}"
                { message: 'Location saved', data: new_loc }.to_json
              rescue Sequel::MassAssignmentRestriction
                Api.logger.warn "MASS-ASSIGNMENT: #{new_data.keys}"
                routing.halt 400, { message: 'Illegal Attributes' }.to_json
              rescue StandardError => e
                Api.logger.error "UNKNOWN ERROR: #{e.message}"
                routing.halt 500, { message: 'Unknown server error' }.to_json
              end
            end

            routing.on 'enrollments' do
              @enrollment_route = "#{@api_root}/courses/#{course_id}/enrollments"

              # DELETE api/v1/courses/[course_id]/enrollments/[enrollment_id]
              routing.on String do |enrollment_id|
                routing.delete do
                  enrollment = Enrollment.first(id: enrollment_id)
                  unless enrollment && enrollment.course_id.to_s == course_id.to_s
                    routing.halt 404, { message: 'Enrollment not found' }.to_json
                  end

                  enrollment.destroy
                  { message: 'Enrollment removed' }.to_json
                rescue StandardError => e
                  Api.logger.error "UNKNOWN ERROR: #{e.message}"
                  routing.halt 500, { message: 'Unknown server error' }.to_json
                end
              end

              # GET api/v1/courses/[course_id]/enrollments
              routing.get do
                output = { data: Course.first(id: course_id).enrollments }
                JSON.pretty_generate(output)
              rescue StandardError
                routing.halt 404, { message: 'Could not find enrollments' }.to_json
              end

              # POST api/v1/courses/[course_id]/enrollments
              routing.post do
                new_data = JSON.parse(routing.body.read)
                account = Account.first(username: new_data['username'])
                routing.halt(404, { message: 'Account not found' }.to_json) unless account

                enrollment = EnrollAccountInCourse.call(
                  account_id: account.id, course_id:,
                  role_name: new_data['role_name']
                )
                raise 'Could not save enrollment' unless enrollment

                response.status = 201
                response['Location'] = "#{@enrollment_route}/#{enrollment.id}"
                { message: 'Enrollment created', data: enrollment }.to_json
              rescue Tyto::EnrollAccountInCourse::UnknownRoleError
                routing.halt 400, { message: 'Unknown role' }.to_json
              rescue Sequel::UniqueConstraintViolation
                routing.halt 409, { message: 'Enrollment already exists' }.to_json
              rescue Sequel::MassAssignmentRestriction
                Api.logger.warn "MASS-ASSIGNMENT: #{new_data.keys}"
                routing.halt 400, { message: 'Illegal Attributes' }.to_json
              rescue StandardError => e
                Api.logger.error "UNKNOWN ERROR: #{e.message}"
                routing.halt 500, { message: 'Unknown server error' }.to_json
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
          rescue Sequel::MassAssignmentRestriction
            Api.logger.warn "MASS-ASSIGNMENT: #{new_data.keys}"
            routing.halt 400, { message: 'Illegal Attributes' }.to_json
          rescue StandardError => e
            Api.logger.error "UNKNOWN ERROR: #{e.message}"
            routing.halt 500, { message: 'Unknown server error' }.to_json
          end
        end
      end
    end
  end
end
