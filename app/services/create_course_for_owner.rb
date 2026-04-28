# frozen_string_literal: true

module Tyto
  # Creates a course and its owner enrollment atomically.
  # A failure at either step rolls back both inserts so a course
  # cannot exist without an owner enrollment.
  class CreateCourseForOwner
    class UnknownOwnerError < StandardError; end
    class UnknownCurrentAccountError < StandardError; end
    class NotAuthorizedError < StandardError; end

    # NOTE: role-checking belongs in a Policy object (see branch 7-policies).
    # It lives here for now to demonstrate the smell that motivates extracting it.
    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def self.call(current_account_id:, owner_id:, course_data:)
      Tyto::Api.DB.transaction do
        current_account = Account.first(id: current_account_id) or raise UnknownCurrentAccountError
        unless current_account.system_roles.map(&:name).intersect?(Role::COURSE_CREATORS)
          raise NotAuthorizedError, 'Only creators or admins can create courses'
        end

        owner = Account.first(id: owner_id) or raise UnknownOwnerError
        course = Course.create(course_data)
        Enrollment.create(account_id: owner.id, course_id: course.id,
                          role_id: Role.first(name: 'owner')&.id)
        course
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
  end
end
