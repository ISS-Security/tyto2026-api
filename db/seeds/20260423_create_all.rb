# frozen_string_literal: true

require 'yaml'

Sequel.seed(:development) do
  def run
    puts 'Seeding roles, accounts, system roles, courses, enrollments, ' \
         'locations, events'
    create_roles
    create_accounts
    assign_system_roles
    create_owned_courses
    create_non_owner_enrollments
    create_locations
    create_events
  end
end

DIR = File.dirname(__FILE__)
ALL_ROLES = %w[admin creator member owner instructor staff student].freeze
ACCOUNTS_INFO    = YAML.load_file("#{DIR}/accounts_seed.yml")
COURSES_INFO     = YAML.load_file("#{DIR}/course_seeds.yml")
ENROLLMENTS_INFO = YAML.load_file("#{DIR}/enrollments_seed.yml")
LOCATIONS_INFO   = YAML.load_file("#{DIR}/location_seeds.yml")
EVENTS_INFO      = YAML.load_file(
  "#{DIR}/event_seeds.yml",
  permitted_classes: [Time]
)

SYSTEM_ROLE_ASSIGNMENTS = {
  'soumya.ray' => %w[admin creator],
  'jerry.ho' => %w[admin creator],
  'galit' => %w[creator],
  'li.wei' => %w[member],
  'chen.hsinyi' => %w[member],
  'wang.ting' => %w[member],
  'lin.chiahao' => %w[member],
  'huang.peijun' => %w[member],
  'tsai.yuting' => %w[member]
}.freeze

def create_roles
  ALL_ROLES.each { |name| Tyto::Role.find_or_create(name:) }
end

def create_accounts
  ACCOUNTS_INFO.each do |account_info|
    Tyto::Account.create(account_info)
  end
end

def assign_system_roles
  SYSTEM_ROLE_ASSIGNMENTS.each do |username, role_names|
    account = Tyto::Account.first(username:)
    role_names.each do |role_name|
      role = Tyto::Role.first(name: role_name)
      account.add_system_role(role)
    end
  end
end

def create_owned_courses
  ENROLLMENTS_INFO
    .select { |row| row['role_name'] == 'owner' }
    .each do |row|
      account = Tyto::Account.first(username: row['username'])
      course_data = COURSES_INFO.find { |c| c['name'] == row['course_name'] }
      Tyto::CreateCourseForOwner.call(
        owner_id: account.id, course_data:
      )
    end
end

def create_non_owner_enrollments
  ENROLLMENTS_INFO
    .reject { |row| row['role_name'] == 'owner' }
    .each { |row| enroll_row(row) }
end

def enroll_row(row)
  account = Tyto::Account.first(username: row['username'])
  course  = Tyto::Course.first(name: row['course_name'])
  Tyto::EnrollAccountInCourse.call(
    account_id: account.id, course_id: course.id, role_name: row['role_name']
  )
end

def create_locations
  courses_cycle = Tyto::Course.all.cycle
  LOCATIONS_INFO.each do |location_data|
    course = courses_cycle.next
    Tyto::CreateLocationForCourse.call(
      course_id: course.id, location_data:
    )
  end
end

def create_events
  courses_cycle = Tyto::Course.all.cycle
  EVENTS_INFO.each do |event_data|
    course = courses_cycle.next
    Tyto::CreateEventForCourse.call(
      course_id: course.id, event_data:
    )
  end
end
