# 7-policies — Policy objects, scopes, and summaries for every resource

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update this plan before and after task and subtask implementations.

## Branch

`7-policies` (off `main`)

## Goal

Replace every scattered inline role check in the API with a **Policy object** per resource, paired with a **Policy Scope** for list-style queries and a **Policy Summary** the App can consume as JSON. This branch is fundamentally a refactoring milestone: no new domain entities, no new routes for read paths. The change is **where authorization decisions live** — moved from inline `current_account.system_roles.intersect?(...)` calls inside services and routes into single-purpose `*Policy` classes under `app/policies/`.

Adapted from the reference branch.

## Strategy: Vertical Slice

1. **`Role` predicates** — Add instance predicates to `Role` (`role.admin?`, `role.teaching?`, `role.course_creator?`, etc.). Existing constants stay; predicates become the canonical path for policies.
2. **Policy objects** — Seven new files under `app/policies/`: `CoursePolicy`, `EventPolicy`, `LocationPolicy`, `AccountPolicy`, `AttendancePolicy`, `EnrollmentPolicy`, `SystemRolePolicy`. Each ships `can_*?` predicates, private helpers, and a `#summary` method.
3. **Policy scopes** — `CoursePolicy::AccountScope`, `EventPolicy::CourseScope`, `AttendancePolicy::EventScope`, `AttendancePolicy::EligibleScope`, `AccountPolicy::AdminScope` — nested under their parent policy file.
4. **Service refactor** — Extract four inline role checks from `CreateCourseForOwner`, `EnrollAccountInCourse`, `AssignSystemRole`, `RecordAttendance` into their corresponding policies.
5. **Route refactor** — Drop per-route inline `Enrollment.first(...)` existence checks scattered through `courses.rb`; replace with policy reads. Drop the inline admin check in `accounts.rb` system-role routes.
6. **JSON envelope** — Every read response gains a `policies: {...}` key, populated by `XPolicy.new(@auth_account, resource).summary`. Index routes carry per-resource summaries.
7. **Tests** — Per-policy unit specs + integration spec updates for the new envelope shape and 403 wiring.

## Current State

- [ ] Plan created
- [ ] Branch `7-policies` created off `main`
- [ ] `Role` instance predicates added
- [ ] `CoursePolicy` + `CoursePolicy::AccountScope`
- [ ] `EventPolicy` + `EventPolicy::CourseScope`
- [ ] `LocationPolicy` + `LocationPolicy::CourseScope`
- [ ] `AccountPolicy` + `AccountPolicy::AdminScope`
- [ ] `AttendancePolicy` + `AttendancePolicy::EventScope` + `AttendancePolicy::EligibleScope`
- [ ] `EnrollmentPolicy`
- [ ] `SystemRolePolicy`
- [ ] `CreateCourseForOwner` calls `CoursePolicy#can_create?`
- [ ] `EnrollAccountInCourse` calls `EnrollmentPolicy#can_manage?`
- [ ] `AssignSystemRole` calls `SystemRolePolicy#can_manage?`
- [ ] `RecordAttendance` calls `AttendancePolicy#can_record?`
- [ ] `courses.rb` route blocks drop inline enrollment-existence checks
- [ ] `accounts.rb` system-role routes drop inline admin check
- [ ] `attendances.rb` `/attendances/eligible` uses `AttendancePolicy::EligibleScope`
- [ ] JSON read envelopes carry `policies:` key (single + index)
- [ ] Tests: `spec/policies/*_spec.rb` per policy
- [ ] Integration specs assert `policies` envelope + correct 403 wiring
- [ ] `rake spec` green
- [ ] `bundle exec rubocop .` green
- [ ] `bundle exec bundle-audit check --update` green
- [ ] Code review
- [ ] Retrospective migration audit
- [ ] Single payload commit shaped
- [ ] Merge PR to `main` — deferred to user
- [ ] Skill self-reflection

## Key Findings

### Starting point (post `6-auth-token`)

- **Inline role checks exist in four services**:
  - `CreateCourseForOwner`: `current_account.system_roles.map(&:name).intersect?(Role::COURSE_CREATORS)`
  - `EnrollAccountInCourse`: same pattern with `Role::TEACHING`
  - `AssignSystemRole`: inline `admin` check
  - `RecordAttendance`: inline `role.name == 'student'` check
- **Route-level inline enrollment existence checks** scattered through `courses.rb`:
  ```ruby
  unless Enrollment.first(account_id: current_account_id, course_id:)
    routing.halt 404, { message: 'Course not found' }.to_json
  end
  ```
  Appears on `GET /courses/:id/events`, `GET /courses/:id/events/:id`, `GET /courses/:id/locations`, `GET /courses/:id/locations/:id`. They're a primitive form of `CoursePolicy#can_view?`.
- **`accounts.rb` system-role routes** have inline admin checks (`current_account.system_roles.map(&:name).include?('admin')`).
- **Bearer token authorization fully in place** — every authenticated route reads `@auth_account` from a verified token. This branch does not touch token plumbing.
- **`Role` constants exist** (`Role::TEACHING`, `Role::COURSE_CREATORS`, `Role::SYSTEM`, `Role::COURSE`). **Predicates do not exist yet** — adding them is step 1.
- **No `app/policies/` directory** — created this branch. Autoload via `require_app.rb` adding `'policies'` to the folders list.

### Threat model delta vs `6-auth-token`

| Risk | Addressed here | Deferred |
| --- | --- | --- |
| Authorization rules scattered across services + routes | Centralized in `app/policies/*Policy` objects | Scope-based auth (per-token scope strings) deferred per project rules |
| Index queries return everything; policy "discovered" at per-resource read | Policy scopes filter at query level — account sees only what `*Policy::Scope#viewable` returns | — |
| Inline role checks read role names from string-array constants — typo-prone | Role predicates (`role.admin?`, `role.teaching?`) replace string matching | — |
| App has to duplicate authorization rules in templates | API emits `policies: {can_X: bool, ...}` summary; App reads it | App-side parser models that consume the summary — deferred per project rules |

### Domain scope (this branch only)

No new entities. `attendances` table, `Attendance` model, `RecordAttendance`, `ListEligibleEvents` all already exist. This branch wraps them with policies.

## Questions

> Q1, Q2, … crossed off with decisions.

- [ ] **Q1 (policy summary shape)**: full Credence-style summary on every read, or only the predicates the App template actually consumes?
  - Recommended: **App-driven slim** — emit only what the App reads this week. Adding fields later is free; removing fields after the App reads them is a breaking change.
- [ ] **Q2 (`Role` predicate placement)**: instance predicates on `Role` (`role.admin?`) or class methods on `Account` (`account.admin?`)?
  - Recommended: **instance on `Role`** — keeps `Account` thin; `Role` knows its own categorization.
- [ ] **Q3 (policy scope file layout)**: separate `*_scopes.rb` file per policy, or scope nested under the policy file?
  - Recommended: **nested under policy file** — one file = one policy surface.
- [ ] **Q4 (`ListEligibleEvents`)**: rename to `AttendancePolicy::EligibleScope`?
  - Recommended: **yes** — `ListEligibleEvents` is a policy scope written without the policy-scope name. Move into the scope.
- [ ] **Q5 (policy summary on write responses)**: emit always, only on reads, or only on writes that don't redirect?
  - Recommended: **read responses only** — keeps the contract focused.

## Scope

**In scope (single payload)**:

- `app/policies/` directory + `require_app.rb` autoload
- `app/policies/course_policy.rb` — `CoursePolicy` + `CoursePolicy::AccountScope`
- `app/policies/event_policy.rb` — `EventPolicy` + `EventPolicy::CourseScope`
- `app/policies/location_policy.rb` — `LocationPolicy` + `LocationPolicy::CourseScope`
- `app/policies/account_policy.rb` — `AccountPolicy` + `AccountPolicy::AdminScope`
- `app/policies/attendance_policy.rb` — `AttendancePolicy` + `AttendancePolicy::EventScope` + `AttendancePolicy::EligibleScope`
- `app/policies/enrollment_policy.rb` — `EnrollmentPolicy`
- `app/policies/system_role_policy.rb` — `SystemRolePolicy`
- `app/models/role.rb` — instance predicates (`admin?`, `creator?`, `teaching?`, etc.)
- Service refactor: `CreateCourseForOwner`, `EnrollAccountInCourse`, `AssignSystemRole`, `RecordAttendance` all drop inline role checks for policy reads
- Route refactor: `courses.rb` drops `Enrollment.first(...)` existence checks; `accounts.rb` drops inline admin check; `attendances.rb` uses `EligibleScope`
- Every read response envelope carries `policies:` key
- Per-policy unit specs + integration spec updates
- Folded in: a small adaptation that tightens service-call signatures to take only FK ids where any caller was passing a hydrated model — for Tyto's services this is mostly a no-op since they already work this way

**Out of scope** (deferred per project rules):

- Token scopes
- Attendance coordinate encryption
- Geofence eligibility (Haversine distance)
- Staff `PUT /attendances/:event_id/:account_id` toggle route
- Removing role-name constants (`Role::TEACHING`, etc.) — kept as back-compat hedge
- App-side resource parser models consuming the new envelope
- Form validation, App-side everything

## Security Concerns Addressed This Week

1. **Centralizing scattered policies** — four parallel inline-check → policy-object extractions + the route-level `Enrollment.first(...)` consolidation. Policy logic moves from "wherever you happen to need it" to a single discoverable home.
2. **Policy objects as a first-class concern** — `app/policies/` becomes a top-level folder alongside `models`, `services`, `controllers`. Easy to find, easy to read, easy to test in isolation.
3. **Predicate-function family** (`can_view?` / `can_edit?` / `can_delete?`) — Ruby-idiomatic boolean methods composed of private helpers (`account_is_owner?`, `account_is_teaching_staff?`). Duplication is acceptable; clarity over cleverness.
4. **Policy scopes as query objects** — index routes consume `*Policy::AccountScope#viewable`; they never assemble the list themselves. Index routes shrink to 2-line bodies.
5. **Server-side policy summary as distribution mechanism** — `#summary` returns a hash merged into the JSON envelope. Templates branch on the summary; no duplication across systems.
6. **Defense in depth via three-layer role taxonomy** — constants → predicates → policies. Each layer independently auditable; a bug in one doesn't silently spread to the other two.

## Tasks

> Check tasks off as soon as each one is finished — do not batch.

### Setup

- [ ] Create branch `7-policies` off `main`
- [ ] Update `CLAUDE.local.md` to point at this plan
- [ ] Plan-first commit (`docs: plan 7-policies`)

### Role predicates

- [ ] `app/models/role.rb`: add instance predicates — `admin?`, `creator?`, `member?` (system roles); `owner?`, `instructor?`, `staff?`, `student?` (course roles); `teaching?` (`%w[owner instructor staff].include?(name)`); `course_creator?` (`%w[creator admin].include?(name)`); `system?`, `course_role?`. Keep constants.
- [ ] `spec/models/role_spec.rb`: predicate-per-role coverage.

### Policy objects

- [ ] `app/policies/course_policy.rb`: `CoursePolicy(account, course)` with `can_view?` / `can_edit?` / `can_delete?` / `can_create?` / `can_enroll?` / `can_record_attendance?`; private helpers; `#summary`. Nested `CoursePolicy::AccountScope(current_account, target_account=nil)` with `#viewable`.
- [ ] `app/policies/event_policy.rb`: `EventPolicy` + `EventPolicy::CourseScope`.
- [ ] `app/policies/location_policy.rb`: `LocationPolicy` + `LocationPolicy::CourseScope`.
- [ ] `app/policies/account_policy.rb`: `AccountPolicy` + `AccountPolicy::AdminScope`.
- [ ] `app/policies/attendance_policy.rb`: `AttendancePolicy` + `AttendancePolicy::EventScope` + `AttendancePolicy::EligibleScope`.
- [ ] `app/policies/enrollment_policy.rb`: `EnrollmentPolicy`.
- [ ] `app/policies/system_role_policy.rb`: `SystemRolePolicy`.
- [ ] `require_app.rb`: add `'policies'` to default folders.

### Service refactor

- [ ] `app/services/create_course_for_owner.rb`: replace inline `intersect?(COURSE_CREATORS)` with `raise NotAuthorizedError unless CoursePolicy.new(current_account, nil).can_create?`.
- [ ] `app/services/enroll_account_in_course.rb`: replace `TEACHING` check with `EnrollmentPolicy.new(current_account, course).can_manage?`.
- [ ] `app/services/assign_system_role.rb`: replace admin check with `SystemRolePolicy.new(current_account, target_account).can_manage?`.
- [ ] `app/services/record_attendance.rb`: replace student check with `AttendancePolicy.new(current_account, event).can_record?`.
- [ ] `app/services/list_eligible_events.rb`: move body into `AttendancePolicy::EligibleScope`; delete or delegate.

### Route refactor

- [ ] `app/controllers/courses.rb`:
  - Drop per-route `Enrollment.first(...)` checks on event/location GETs; replace with `course = Course[course_id]; routing.halt 404 unless course && CoursePolicy.new(current_account, course).can_view?`.
  - `GET /courses` (index): call `CoursePolicy::AccountScope.new(current_account).viewable`.
  - `GET /courses/:id`: merge `policies: policy.summary` into envelope.
  - `POST /courses`: policy check now happens in the service.
- [ ] `app/controllers/courses.rb` (events / locations sub-routes): use `EventPolicy` / `LocationPolicy`.
- [ ] `app/controllers/courses.rb` (attendances sub-routes): replace inline `TEACHING` check on `GET /courses/:id/attendances/:event_id` with `AttendancePolicy.new(current_account, event).can_manage?`.
- [ ] `app/controllers/accounts.rb` (system-role routes): replace inline admin check with `SystemRolePolicy`.
- [ ] `app/controllers/attendances.rb`: `GET /attendances/eligible` switches to `AttendancePolicy::EligibleScope.new(current_account).events`.

### JSON envelope policies

- [ ] Read routes merge `policies: XPolicy.new(current_account, resource).summary` into the envelope. Avoid putting policy into the model — the model doesn't know who's asking.
- [ ] Single-resource reads: `course.to_h.merge(policies: ...).to_json`.
- [ ] Index reads: `{ data: courses.map { |c| c.to_h.merge(policies: ...) } }.to_json`.
- [ ] Events (`as_hash_for` from `6-auth-token`): merge `policies` into its output.

### Tests

- [ ] `spec/policies/course_policy_spec.rb`: HAPPY/SAD per predicate per role (owner, instructor, staff, student, enrolled-only, non-enrolled, admin). Cover `#summary` shape.
- [ ] `spec/policies/course_policy_scope_spec.rb`: `AccountScope#viewable` — self returns enrolled courses; admin returns all; non-enrolled returns empty for foreign target.
- [ ] `spec/policies/event_policy_spec.rb`, `location_policy_spec.rb`, `account_policy_spec.rb`, `attendance_policy_spec.rb`, `enrollment_policy_spec.rb`, `system_role_policy_spec.rb`: same pattern.
- [ ] `spec/policies/attendance_eligible_scope_spec.rb`: covers what `ListEligibleEvents` covered.
- [ ] Update `spec/integration/api_courses_spec.rb`: assert `policies` envelope; assert 403 wiring on edit/delete by non-owner.
- [ ] Update `spec/integration/api_accounts_spec.rb`, `api_attendances_spec.rb`, `api_enrollments_spec.rb`: 403 paths stay green; same external behavior.
- [ ] Update service specs: same `NotAuthorizedError` assertions, now raised by policy.

### Verify

- [ ] `bundle exec rake spec` green
- [ ] `bundle exec rubocop .` green
- [ ] `bundle exec bundle-audit check --update` green
- [ ] Manual smoke test: API on :3000, hit `GET /api/v1/courses/<id>` with a student Bearer token → response carries `policies.can_edit: false, can_record_attendance: true`. As owner → `can_edit: true`.
- [ ] Code review
- [ ] Retrospective migration audit (`git show --name-status` cross-check + full-tree + shared-file content diff)
- [ ] Single payload commit shaped
- [ ] Merge PR to `main` — deferred to user, done manually after class
- [ ] Skill self-reflection

## Commit strategy

- **Required commit count**: **1 payload**.
- **Final branch shape**:
  ```
  docs: plan 7-policies
  Uses security policies to manage all resources                ← Single payload
  ```
- **Payload subject**: `Uses security policies to manage all resources`.
- **Body** notes: four parallel inline-check → policy-object extractions; `Role` constants → predicates upgrade; policy-summary slim shape per Q1; small service-signature touchup folded in.

## Infrastructure setup

No new cloud infrastructure this week. Pure code + tests. No new env vars, no new gems, no new external services.

## Completed

(to be filled in during implementation)

## Post-Implementation Notes (for reviewer)

(to be filled in before handing off for review)

---

Last updated: 2026-05-21 (plan created)
