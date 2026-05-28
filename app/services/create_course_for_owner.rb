# frozen_string_literal: true

module Tyto
  # Creates a course and its owner enrollment atomically.
  # A failure at either step rolls back both inserts so a course
  # cannot exist without an owner enrollment.
  class CreateCourseForOwner
    class UnknownOwnerError < StandardError; end
    class UnknownCurrentAccountError < StandardError; end
    class NotAuthorizedError < StandardError; end

    def self.call(current_account_id:, owner_id:, course_data:, auth_scope: AuthScope.new)
      Tyto::Api.DB.transaction do
        current_account = Account.first(id: current_account_id) or raise UnknownCurrentAccountError
        unless auth_scope.can_write?('courses') && AccountPolicy.new(current_account).can_create_course?
          raise NotAuthorizedError, 'Only creators or admins can create courses'
        end

        owner = Account.first(id: owner_id) or raise UnknownOwnerError
        course = Course.create(course_data)
        course.add_enrollment(account_id: owner.id, role_id: Role.id_for('owner'))
        course
      end
    end
  end
end
