# frozen_string_literal: true

require 'roda'
require_relative 'app'

module Tyto
  # Web controller for Tyto API
  class Api < Roda # rubocop:disable Metrics/ClassLength
    route('courses') do |routing|
      @course_route = "#{@api_root}/courses"
      current_account_id = @auth_account&.dig('attributes', 'id')
      routing.halt(401, { message: 'Authentication required' }.to_json) unless current_account_id

      routing.on String do |course_id|
        routing.on 'events' do
          @event_route = "#{@api_root}/courses/#{course_id}/events"

          # GET api/v1/courses/[course_id]/events/[event_id]
          routing.get String do |event_id|
            unless Enrollment.first(account_id: current_account_id, course_id:)
              routing.halt 404, { message: 'Course not found' }.to_json
            end

            event = Event.where(course_id:, id: event_id).first
            event ? event.as_hash_for(current_account_id).to_json : raise('Event not found')
          rescue StandardError => e
            routing.halt 404, { message: e.message }.to_json
          end

          # GET api/v1/courses/[course_id]/events
          routing.get do
            unless Enrollment.first(account_id: current_account_id, course_id:)
              routing.halt 404, { message: 'Course not found' }.to_json
            end

            payload = Course.first(id: course_id).events.map { |e| e.as_hash_for(current_account_id) }
            { data: payload }.to_json
          rescue StandardError
            routing.halt 404, { message: 'Could not find events' }.to_json
          end

          # POST api/v1/courses/[course_id]/events
          routing.post do
            body = HttpRequest.new(routing).body_data
            event_data = body.slice(:name, :start_at, :end_at, :location_id)
            new_event = CreateEventForCourse.call(
              current_account_id:, course_id:, event_data:
            )
            raise 'Could not save event' unless new_event

            response.status = 201
            response['Location'] = "#{@event_route}/#{new_event.id}"
            { message: 'Event saved', data: new_event }.to_json
          rescue Tyto::CreateEventForCourse::NotAuthorizedError => e
            routing.halt 403, { message: e.message }.to_json
          rescue StandardError => e
            Api.logger.error "UNKNOWN ERROR: #{e.message}"
            routing.halt 500, { message: 'Unknown server error' }.to_json
          end
        end

        routing.on 'locations' do
          @location_route = "#{@api_root}/courses/#{course_id}/locations"

          # GET api/v1/courses/[course_id]/locations/[location_id]
          routing.get String do |location_id|
            unless Enrollment.first(account_id: current_account_id, course_id:)
              routing.halt 404, { message: 'Course not found' }.to_json
            end

            loc = Location.where(course_id:, id: location_id).first
            loc ? loc.to_json : raise('Location not found')
          rescue StandardError => e
            routing.halt 404, { message: e.message }.to_json
          end

          # GET api/v1/courses/[course_id]/locations
          routing.get do
            unless Enrollment.first(account_id: current_account_id, course_id:)
              routing.halt 404, { message: 'Course not found' }.to_json
            end

            output = { data: Course.first(id: course_id).locations }
            JSON.pretty_generate(output)
          rescue StandardError
            routing.halt 404, { message: 'Could not find locations' }.to_json
          end

          # POST api/v1/courses/[course_id]/locations
          routing.post do
            body = HttpRequest.new(routing).body_data
            location_data = body.slice(:name, :longitude, :latitude)
            new_loc = CreateLocationForCourse.call(
              current_account_id:, course_id:, location_data:
            )
            raise 'Could not save location' unless new_loc

            response.status = 201
            response['Location'] = "#{@location_route}/#{new_loc.id}"
            { message: 'Location saved', data: new_loc }.to_json
          rescue Tyto::CreateLocationForCourse::NotAuthorizedError => e
            routing.halt 403, { message: e.message }.to_json
          rescue StandardError => e
            Api.logger.error "UNKNOWN ERROR: #{e.message}"
            routing.halt 500, { message: 'Unknown server error' }.to_json
          end
        end

        routing.on 'attendances' do
          @attendance_route = "#{@api_root}/courses/#{course_id}/attendances"

          # GET api/v1/courses/[course_id]/attendances/[event_id]
          # Teaching-staff: every student's attendance for one event.
          routing.get String do |event_id|
            caller_roles = Enrollment.where(account_id: current_account_id, course_id:)
                                     .map { |e| e.role&.name }
            unless caller_roles.intersect?(Role::TEACHING)
              routing.halt 403, { message: 'Only teaching staff can view event attendances' }.to_json
            end

            attendances = Attendance.where(course_id:, event_id:).all
            { data: attendances }.to_json
          rescue StandardError => e
            Api.logger.error "UNKNOWN ERROR: #{e.message}"
            routing.halt 500, { message: 'Unknown server error' }.to_json
          end

          # POST api/v1/courses/[course_id]/attendances
          # Student check-in for an event.
          routing.post do
            body = HttpRequest.new(routing).body_data
            attendance = RecordAttendance.call(
              current_account_id:, course_id:, event_id: body[:event_id]
            )

            response.status = 201
            response['Location'] = "#{@attendance_route}/#{attendance.id}"
            { message: 'Attendance recorded', data: attendance }.to_json
          rescue Tyto::RecordAttendance::NotAuthorizedError => e
            routing.halt 403, { message: e.message }.to_json
          rescue Tyto::RecordAttendance::UnknownEventError => e
            routing.halt 404, { message: e.message }.to_json
          rescue Tyto::RecordAttendance::NotLiveError => e
            routing.halt 422, { message: e.message }.to_json
          rescue Sequel::UniqueConstraintViolation
            routing.halt 409, { message: 'Attendance already recorded' }.to_json
          rescue StandardError => e
            Api.logger.error "UNKNOWN ERROR: #{e.message}"
            routing.halt 500, { message: 'Unknown server error' }.to_json
          end

          # GET api/v1/courses/[course_id]/attendances
          # Caller's own attendances for this course.
          routing.get do
            unless Enrollment.first(account_id: current_account_id, course_id:)
              routing.halt 404, { message: 'Course not found' }.to_json
            end

            output = { data: Attendance.where(account_id: current_account_id, course_id:).all }
            output.to_json
          rescue StandardError
            routing.halt 404, { message: 'Could not find attendances' }.to_json
          end
        end

        routing.on 'enrollments' do
          @enrollment_route = "#{@api_root}/courses/#{course_id}/enrollments"

          routing.on String do |segment|
            # DELETE api/v1/courses/[course_id]/enrollments/[enrollment_id]
            routing.delete do
              current_role_names = Enrollment.where(account_id: current_account_id, course_id:)
                                             .map { |e| e.role&.name }
              unless current_role_names.intersect?(Role::TEACHING)
                routing.halt 403, { message: 'Only teaching staff can remove enrollments' }.to_json
              end

              enrollment = Enrollment.first(id: segment)
              unless enrollment && enrollment.course_id.to_s == course_id.to_s
                routing.halt 404, { message: 'Enrollment not found' }.to_json
              end

              enrollment.destroy
              { message: 'Enrollment removed' }.to_json
            rescue StandardError => e
              Api.logger.error "UNKNOWN ERROR: #{e.message}"
              routing.halt 500, { message: 'Unknown server error' }.to_json
            end

            # POST api/v1/courses/[course_id]/enrollments/[username]
            routing.post do
              body = HttpRequest.new(routing).body_data
              target = Account.first(username: segment)
              routing.halt(404, { message: 'Account not found' }.to_json) unless target

              enrollment = EnrollAccountInCourse.call(
                current_account_id:,
                target_account_id: target.id,
                course_id:,
                role_name: body[:role_name]
              )
              raise 'Could not save enrollment' unless enrollment

              response.status = 201
              response['Location'] = "#{@enrollment_route}/#{enrollment.id}"
              { message: 'Enrollment created', data: enrollment }.to_json
            rescue Tyto::EnrollAccountInCourse::NotAuthorizedError => e
              routing.halt 403, { message: e.message }.to_json
            rescue Tyto::EnrollAccountInCourse::UnknownRoleError
              routing.halt 400, { message: 'Unknown role' }.to_json
            rescue Sequel::UniqueConstraintViolation
              routing.halt 409, { message: 'Enrollment already exists' }.to_json
            rescue StandardError => e
              Api.logger.error "UNKNOWN ERROR: #{e.message}"
              routing.halt 500, { message: 'Unknown server error' }.to_json
            end
          end

          # GET api/v1/courses/[course_id]/enrollments
          routing.get do
            unless Enrollment.first(account_id: current_account_id, course_id:)
              routing.halt 404, { message: 'Course not found' }.to_json
            end

            output = { data: Course.first(id: course_id).enrollments }
            JSON.pretty_generate(output)
          rescue StandardError
            routing.halt 404, { message: 'Could not find enrollments' }.to_json
          end
        end

        # GET api/v1/courses/[course_id]
        routing.get do
          unless Enrollment.first(account_id: current_account_id, course_id:)
            routing.halt 404, { message: 'Course not found' }.to_json
          end

          course = Course.first(id: course_id)
          course ? course.to_json : raise('Course not found')
        rescue StandardError => e
          routing.halt 404, { message: e.message }.to_json
        end
      end

      # GET api/v1/courses
      # Returns only courses the authenticated account is enrolled in.
      routing.get do
        account = Account.first(id: current_account_id)
        output = { data: account ? account.courses.uniq : [] }
        JSON.pretty_generate(output)
      rescue StandardError
        routing.halt 404, { message: 'Could not find courses' }.to_json
      end

      # POST api/v1/courses
      routing.post do
        body = HttpRequest.new(routing).body_data
        course_data = body.slice(:name, :description)
        new_course = CreateCourseForOwner.call(
          current_account_id:, owner_id: current_account_id, course_data:
        )

        response.status = 201
        response['Location'] = "#{@course_route}/#{new_course.id}"
        { message: 'Course saved', data: new_course }.to_json
      rescue Tyto::CreateCourseForOwner::NotAuthorizedError => e
        routing.halt 403, { message: e.message }.to_json
      rescue Sequel::MassAssignmentRestriction
        Api.logger.warn "MASS-ASSIGNMENT: #{body.keys}"
        routing.halt 400, { message: 'Illegal Attributes' }.to_json
      rescue StandardError => e
        Api.logger.error "UNKNOWN ERROR: #{e.message}"
        routing.halt 500, { message: 'Unknown server error' }.to_json
      end
    end
  end
end
