# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test GeoFence' do
  # A 55 m fence centred at (lat 24.0, lon 121.0).
  let(:fence) { Tyto::GeoFence.new(lat: 24.0, lon: 121.0, radius_m: 55) }

  it 'GEO: contains its exact centre point' do
    _(fence.contains?(24.0, 121.0)).must_equal true
    _(fence.distance_to(24.0, 121.0)).must_be :<, 1.0
  end

  it 'GEO: a point ~11 m away is inside a 55 m radius' do
    # 0.0001 deg latitude ~= 11 m
    _(fence.contains?(24.0001, 121.0)).must_equal true
  end

  it 'GEO: a point ~111 m away is outside a 55 m radius' do
    # 0.001 deg latitude ~= 111 m
    _(fence.contains?(24.001, 121.0)).must_equal false
  end

  it 'GEO: a far-away point is well out of range' do
    _(fence.contains?(24.5, 121.5)).must_equal false
  end

  it 'GEO: distance_to approximates the great-circle distance in metres' do
    # 0.001 deg latitude ~= 111.2 m
    _(fence.distance_to(24.001, 121.0)).must_be_close_to 111.2, 1.0
  end

  it 'GEO: coerces string coordinates (as the Location model stores them)' do
    fence = Tyto::GeoFence.new(lat: '24.0', lon: '121.0', radius_m: '55')
    _(fence.contains?('24.0', '121.0')).must_equal true
  end

  it 'GEO: raises on non-numeric coordinates' do
    _ { Tyto::GeoFence.new(lat: 'abc', lon: '121.0', radius_m: 55) }.must_raise ArgumentError
  end
end
