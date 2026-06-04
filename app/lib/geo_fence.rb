# frozen_string_literal: true

module Tyto
  # A circular geofence: pure great-circle geometry centred on (lat, lon) with
  # a radius in metres. `contains?` is true when a point lies within the radius.
  #
  # Deliberately domain-agnostic -- it knows nothing about events, attendance,
  # config, or "what to do when there is no place". Callers supply the centre
  # and radius and ask a geometric question. Distance is the great-circle
  # (haversine) distance. Inputs are coerced with Float, so string coordinates
  # (as stored by the Location model) work; non-numeric input raises ArgumentError.
  class GeoFence
    EARTH_RADIUS_M = 6_371_000.0

    def initialize(lat:, lon:, radius_m:)
      @lat = Float(lat)
      @lon = Float(lon)
      @radius_m = Float(radius_m)
    end

    def contains?(lat, lon)
      distance_to(lat, lon) <= @radius_m
    end

    def distance_to(lat, lon)
      haversine(@lat, @lon, Float(lat), Float(lon))
    end

    private

    def radians(degrees)
      degrees * Math::PI / 180
    end

    # Great-circle distance via the haversine formula (a standard closed-form
    # expression -- kept whole rather than split for readability).
    # rubocop:disable Metrics/AbcSize
    def haversine(lat1, lon1, lat2, lon2)
      half_dlat = radians(lat2 - lat1) / 2
      half_dlon = radians(lon2 - lon1) / 2
      a = (Math.sin(half_dlat)**2) +
          (Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * (Math.sin(half_dlon)**2))
      EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    end
    # rubocop:enable Metrics/AbcSize
  end
end
