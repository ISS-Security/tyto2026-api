# frozen_string_literal: true

require_relative '../spec_helper'

# Shared fixture helpers for policy specs. Each describe block calls
# `setup_policy_world` in its `before` to seed the same role/account/
# course topology — keeps each spec readable as a single role-by-role
# truth table.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
module PolicyWorld
  ALL_ROLE_NAMES = %w[admin creator member owner instructor staff student].freeze

  def setup_policy_world
    wipe_database
    seed_roles
    seed_accounts
    seed_course_with_enrollments
    seed_event_and_location
  end

  def seed_roles
    ALL_ROLE_NAMES.each { |n| Tyto::Role.find_or_create(name: n) }
  end

  def seed_accounts
    @admin = Tyto::Account.create(DATA[:accounts][0])
    @admin.add_system_role(Tyto::Role.first(name: 'admin'))

    @creator = Tyto::Account.create(DATA[:accounts][1])
    @creator.add_system_role(Tyto::Role.first(name: 'creator'))

    @member = Tyto::Account.create(DATA[:accounts][2])
    @member.add_system_role(Tyto::Role.first(name: 'member'))

    @outsider = Tyto::Account.create(DATA[:accounts][3])
  end

  def seed_course_with_enrollments
    course_data = DATA[:courses][0]
    @course = Tyto::CreateCourseForOwner.call(
      current_account_id: @creator.id, owner_id: @creator.id, course_data:
    )

    @instructor = Tyto::Account.create(DATA[:accounts][4])
    Tyto::Enrollment.create(
      account_id: @instructor.id, course_id: @course.id,
      role_id: Tyto::Role.id_for('instructor')
    )

    @staff = Tyto::Account.create(DATA[:accounts][5])
    Tyto::Enrollment.create(
      account_id: @staff.id, course_id: @course.id,
      role_id: Tyto::Role.id_for('staff')
    )

    @student = Tyto::Account.create(DATA[:accounts][6])
    Tyto::Enrollment.create(
      account_id: @student.id, course_id: @course.id,
      role_id: Tyto::Role.id_for('student')
    )
  end

  def seed_event_and_location
    @location = Tyto::CreateLocationForCourse.call(
      current_account_id: @creator.id, course_id: @course.id,
      location_data: { name: 'Room A', longitude: '121.0', latitude: '24.0' }
    )

    now = Time.now
    @live_event = Tyto::CreateEventForCourse.call(
      current_account_id: @creator.id, course_id: @course.id,
      event_data: {
        name: 'Live Class', location_id: @location.id,
        start_at: now - 600, end_at: now + 600
      }
    )
    @future_event = Tyto::CreateEventForCourse.call(
      current_account_id: @creator.id, course_id: @course.id,
      event_data: {
        name: 'Future Class', location_id: @location.id,
        start_at: now + 3600, end_at: now + 7200
      }
    )
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
