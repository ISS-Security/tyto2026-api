# frozen_string_literal: true

require_relative 'policy_helper'

describe 'CoursePolicy::AccountScope' do
  include PolicyWorld

  before { setup_policy_world }

  it 'HAPPY: owner sees only their enrolled courses' do
    viewable = Tyto::CoursePolicy::AccountScope.new(@creator).viewable
    _(viewable.map(&:id)).must_include @course.id
  end

  it 'HAPPY: admin sees every course' do
    viewable = Tyto::CoursePolicy::AccountScope.new(@admin).viewable
    _(viewable.map(&:id)).must_include @course.id
  end

  it 'SAD: outsider sees no courses' do
    viewable = Tyto::CoursePolicy::AccountScope.new(@outsider).viewable
    _(viewable).must_equal []
  end

  # Scope ↔ policy consistency cross-checks: every course the scope returns
  # must also satisfy CoursePolicy#can_view? (and every course the scope
  # rejects must NOT satisfy it). Catches the canonical drift risk of
  # expressing the rule as both a SQL filter and a predicate.
  describe 'scope ↔ policy consistency' do
    [%i[creator @creator], %i[student @student], %i[outsider @outsider],
     %i[admin @admin]].each do |label, ivar|
      it "consistency: #{label}" do
        account = instance_variable_get(ivar)
        viewable_ids = Tyto::CoursePolicy::AccountScope.new(account).viewable.map(&:id)
        all_courses = Tyto::Course.all
        all_courses.each do |c|
          actual = Tyto::CoursePolicy.new(account, c).can_view?
          expected = viewable_ids.include?(c.id)
          _(actual).must_equal(expected,
            "Scope/policy disagree for #{label} on course #{c.id}")
        end
      end
    end
  end
end
