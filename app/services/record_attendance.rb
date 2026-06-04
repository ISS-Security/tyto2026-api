# frozen_string_literal: true

module Tyto
  # Records that the calling account attended a specific event. Check-in
  # requires the right role (enrolled student), the right time (event live
  # now), and the right place (within the geofence of the event's location).
  # Authorization sits behind AttendancePolicy; the place check uses GeoFence
  # (pure geometry). The attendance-domain rules -- the radius, where it comes
  # from, and "no location means no geofence to enforce" -- live here.
  # Submitted coordinates are stored encrypted at rest.
  class RecordAttendance
    DEFAULT_RADIUS_M = 55.0

    class NotAuthorizedError < StandardError; end
    class UnknownEventError < StandardError; end
    class UnknownCurrentAccountError < StandardError; end
    class NotLiveError < StandardError; end
    class OutOfRangeError < StandardError; end
    class InvalidCoordinatesError < StandardError; end

    def self.call(current_account_id:, course_id:, event_id:, coordinates:, auth_scope: AuthScope.new)
      current_account = Account.first(id: current_account_id) or raise UnknownCurrentAccountError
      event = Event.first(id: event_id, course_id:)
      raise UnknownEventError, 'Event not found' unless event

      ensure_can_record!(current_account, event, auth_scope)
      ensure_in_range!(event, coordinates)

      Attendance.create(
        account_id: current_account_id, course_id:, event_id: event.id,
        checked_in_at: Time.now,
        longitude: coordinates[:longitude], latitude: coordinates[:latitude]
      )
    end

    # Role (enrolled student) + time (event live now).
    def self.ensure_can_record!(account, event, auth_scope)
      raise NotAuthorizedError, 'Only enrolled students can check in' unless
        CoursePolicy.new(account, event.course, auth_scope:).can_record_attendance?
      raise NotLiveError, 'Event is not live right now' unless
        AttendancePolicy.new(account, event, auth_scope:).can_record?
    end

    # Place: the submitted point must fall inside the event location's geofence.
    # Coordinates are always validated (a bad submission is a 400 even when the
    # event has no location); an event without a location has no fence to clear.
    def self.ensure_in_range!(event, coordinates)
      lat, lon = parse_point(coordinates)
      location = event.location
      return unless location

      fence = GeoFence.new(lat: location.latitude, lon: location.longitude, radius_m: configured_radius)
      raise OutOfRangeError, 'You are not at the event location' unless fence.contains?(lat, lon)
    end

    def self.parse_point(coordinates)
      [Float(coordinates[:latitude]), Float(coordinates[:longitude])]
    rescue ArgumentError, TypeError
      raise InvalidCoordinatesError, 'Valid longitude and latitude are required'
    end

    def self.configured_radius
      raw = (Tyto::Api.config.ATTENDANCE_RADIUS_M if defined?(Tyto::Api) && Tyto::Api.respond_to?(:config))
      raw ? raw.to_f : DEFAULT_RADIUS_M
    end
  end
end
