# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Test Event Handling' do
  before do
    wipe_database

    DATA[:courses].each do |course_data|
      Tyto::Course.create(course_data)
    end
  end

  it 'HAPPY: should retrieve correct data from database' do
    event_data = DATA[:events][1]
    course = Tyto::Course.first
    new_event = course.add_event(event_data)

    event = Tyto::Event.find(id: new_event.id)
    _(event.name).must_equal event_data['name']
  end

  it 'SECURITY: should not use deterministic integers as ID' do
    event_data = DATA[:events][1]
    course = Tyto::Course.first
    new_event = course.add_event(event_data)

    _(new_event.id.is_a?(Numeric)).must_equal false
  end
end
