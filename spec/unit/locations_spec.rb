# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Location Handling' do
  before do
    wipe_database

    DATA[:courses].each do |course_data|
      Tyto::Course.create(course_data)
    end
  end

  it 'HAPPY: should retrieve correct data from database' do
    loc_data = DATA[:locations][1]
    course = Tyto::Course.first
    new_loc = course.add_location(loc_data)

    loc = Tyto::Location.find(id: new_loc.id)
    _(loc.name).must_equal loc_data['name']
    _(loc.longitude).must_equal loc_data['longitude']
    _(loc.latitude).must_equal loc_data['latitude']
  end

  it 'SECURITY: should secure sensitive attributes' do
    loc_data = DATA[:locations][1]
    course = Tyto::Course.first
    new_loc = course.add_location(loc_data)
    stored_loc = app.DB[:locations].first

    _(stored_loc[:longitude_secure]).wont_equal new_loc.longitude
    _(stored_loc[:latitude_secure]).wont_equal new_loc.latitude
  end
end
