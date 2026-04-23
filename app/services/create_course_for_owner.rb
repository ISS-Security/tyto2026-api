# frozen_string_literal: true

module Tyto
  # Creates a course and its owner enrollment atomically.
  # A failure at either step rolls back both inserts so a course
  # cannot exist without an owner enrollment.
  class CreateCourseForOwner
    class UnknownOwnerError < StandardError; end

    def self.call(owner_id:, course_data:)
      Tyto::Api.DB.transaction do
        account = Account.first(id: owner_id) or raise UnknownOwnerError
        course = Course.create(course_data)
        Enrollment.create(account_id: account.id, course_id: course.id,
                          role_id: Role.first(name: 'owner')&.id)
        course
      end
    end
  end
end
