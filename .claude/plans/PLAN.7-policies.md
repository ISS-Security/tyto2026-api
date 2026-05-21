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
6. **JSON envelope** — Two distinct envelope keys:
   - **`policies`** on every resource read. Entity-scoped: "what can the requesting actor do to *this* resource?" Tiered — single-resource reads emit `#summary` (full), index reads emit `#index_summary` (slim).
   - **`capabilities`** only on the self-Account envelope. Actor-scoped: "what can the requesting actor do, independent of any resource?" Same payload every call for a given actor (cacheable App-side).
   `AccountPolicy` is the one policy with both surfaces (`#summary` + `#capabilities`). Other resources carry `policies` only.
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
- [ ] `CreateCourseForOwner` calls `AccountPolicy#can_create_course?` (per D4 — actor-scoped predicate on `AccountPolicy`, not `CoursePolicy`)
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
- [ ] Diff review against the reference branch
- [ ] Single payload commit shaped
- [ ] Merge PR to `main` — deferred to user

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
| Authorization rules scattered across services + routes | Centralized in `app/policies/*Policy` objects | Scope-based auth (per-token scope strings) (deferred) |
| Index queries return everything; policy "discovered" at per-resource read | Policy scopes filter at query level — account sees only what `*Policy::Scope#viewable` returns | — |
| Inline role checks read role names from string-array constants — typo-prone | Role predicates (`role.admin?`, `role.teaching?`) replace string matching | — |
| App has to duplicate authorization rules in templates | API emits `policies: {can_X: bool, ...}` summary; App reads it | App-side parser models that consume the summary — (deferred) |

### Domain scope (this branch only)

No new entities. `attendances` table, `Attendance` model, `RecordAttendance`, `ListEligibleEvents` all already exist. This branch wraps them with policies.

## Questions

> Q1, Q2, … crossed off with decisions.

- [x] **Q1 (policy summary shape).** Tiered + entity/system split:
  - **Tiered**: single-resource reads emit `#summary` (full); index reads emit `#index_summary` (slim — only predicates the index template branches on).
  - **Entity vs system split**: entity-scoped predicates (`can_edit`, `can_delete`, etc.) live in the resource envelope's `policies` key. Actor-scoped predicates (`is_admin`, `can_create_course`, `can_manage_system_roles`) live in a separate `capabilities` key on the self-Account envelope only. Same payload every call for a given actor; not duplicated on every resource.
  - **`AccountPolicy` has both surfaces**: `#summary` (entity-scoped — runs for self and other) and `#capabilities` (actor-scoped — emitted only when the envelope is the requesting actor's own account). Plus `#index_summary` for `AdminScope` listings.
- [x] **Q2 (`Role` predicate placement).** Instance predicates on `Role` (`role.admin?`, `role.teaching?`, etc.). Policies write `current_account.system_roles.any?(&:admin?)`. `Role` owns its categorization; `Account` stays thin.
- [x] **Q3 (policy scope file layout).** **Separate `*_scopes.rb` files** per policy. Class names stay namespaced (`CoursePolicy::AccountScope`) via class reopening across files. Rationale: scopes re-express the rule as SQL filters (calling the predicate per-row would N+1), so they share little executable code with the policy. Separate files keep per-file length bounded and let scope specs use DB fixtures while policy specs stay in-memory.
- [x] **Q4 (`ListEligibleEvents`).** Renamed to `AttendancePolicy::EligibleScope` and moved into `app/policies/attendance_scopes.rb`. The original service file is deleted outright; callers update to `AttendancePolicy::EligibleScope.new(current_account).events`.
- [x] **Q5 (policy summary on write responses).** Read responses only. Writes do not carry `policies`. If a future write-response consumer appears (e.g. wizard-style flow that needs button-enable state without a redirect), add it then.

## Decisions (D1–D6)

Resolved 2026-05-21 — the items surfaced after closing Q1–Q5 (formerly tracked in the planning repo's `PENDING.decisions.md`, now deleted). D2 and D3 are App-side (see `tyto2026-app/.claude/plans/PLAN.4-validation.md`). D1, D4, D5, D6 are API-side and recorded here.

### D1 — `#index_summary` predicate set per policy (confirmed default)

Per-policy contents:

| Policy | `#summary` (full, single-resource read) | `#index_summary` (slim, list row) |
| --- | --- | --- |
| `CoursePolicy` | `can_view`, `can_edit`, `can_delete`, `can_enroll`, `can_record_attendance` | `can_view`, `can_edit` |
| `EventPolicy` | `can_view`, `can_edit`, `can_delete`, `can_record_attendance` | `can_view`, `can_edit`, `can_record_attendance` |
| `LocationPolicy` | `can_view`, `can_edit`, `can_delete` | `can_view`, `can_edit` |
| `AttendancePolicy` | `can_view`, `can_record`, `can_manage` | `can_view` |
| `EnrollmentPolicy` | `can_manage`, `can_leave` | `can_manage` |
| `SystemRolePolicy` | `can_manage` | — (no list route this branch) |
| `AccountPolicy#summary` (entity) | `can_view`, `can_edit`, `can_delete`, `can_assign_role`, `can_revoke_role` | `can_view`, `can_edit`, `can_assign_role` |
| `AccountPolicy#capabilities` (actor) | `is_admin`, `can_create_course`, `can_manage_system_roles` | n/a — only on the self-Account envelope, not on list rows |

### D4 — Actor-scoped predicate location (overridden to Option 5)

**Overridden** from the original default (class method `CoursePolicy.can_create?`) and from all instance-method-on-resource-policy variants. Actor-scoped predicates move to `AccountPolicy`. Resource policies stay uniformly resource-bound.

Predicates that move to `AccountPolicy` (rule-owners; no cross-policy delegation from this side):

- `AccountPolicy#is_admin?` — `@viewer.system_roles.any?(&:admin?)`
- `AccountPolicy#can_create_course?` — `@viewer.system_roles.any?(&:course_creator?)`
- `AccountPolicy#can_manage_system_roles?` — delegates to `is_admin?`

**`AccountPolicy` constructor**: `initialize(viewer, target = viewer)`. Actor predicates use `@viewer`; entity predicates use `@target`. Default `target = viewer` lets actor-only calls drop the second arg: `AccountPolicy.new(current_account).can_create_course?`.

**`#capabilities` becomes self-referential**: `{ is_admin:, can_create_course:, can_manage_system_roles: }` — calls own methods; no delegation to `CoursePolicy.can_create?` or `SystemRolePolicy#can_manage?`.

**Call-site shape**:

- `CreateCourseForOwner`: `raise NotAuthorizedError unless AccountPolicy.new(current_account).can_create_course?`
- `SystemRolePolicy#can_manage?(target_account)` stays (resource-bound — adds per-target rules like "can't revoke own admin"). Its body delegates the actor half to `AccountPolicy.new(@viewer).can_manage_system_roles?` and adds per-target constraints.
- `CoursePolicy` carries **no** `can_create?` predicate. Removed entirely.

**Rationale**: mirrors the Q1 entity/actor envelope split at the policy-class level. `policies` envelope ← entity-scoped resource policies; `capabilities` envelope ← actor-scoped `AccountPolicy`. Removes the constructor-asymmetry or class-method exception inside `CoursePolicy`. Sets up `8-auth-scope` cleanly — token scopes will narrow capabilities per-token, no policy-class reshuffle needed.

**Cascading edits applied** in the Tasks (Policy objects, Service refactor, Tests), Current State, and Scope sections below.

### D5 — Capabilities-formalization slide (confirmed: land in week 13)

Single slide bridging week-12 informal capabilities concept to the week-13 concrete `capabilities` envelope key. Deck-side concern; planning-repo plan (`baby_tyto/.claude/plans/PLAN.api.7-policies.md`) carries the full deck update notes.

### D6 — Scope/policy-consistency slide (confirmed: land in week 13)

Single slide framing the cost of separating policy scopes from policy predicates (rule re-expressed in SQL → drift risk → mitigation via cross-check tests). Already implemented in the per-scope spec template under "Tests" below. About *policy scopes* (the `CoursePolicy::AccountScope` pattern shipping this week), **not** *auth scopes* (next week's `8-auth-scope` branch).

## Scope

**In scope (single payload)**:

- `app/policies/` directory + `require_app.rb` autoload
- `app/policies/course_policy.rb` — `CoursePolicy`
- `app/policies/course_scopes.rb` — `CoursePolicy::AccountScope`
- `app/policies/event_policy.rb` — `EventPolicy`
- `app/policies/event_scopes.rb` — `EventPolicy::CourseScope`
- `app/policies/location_policy.rb` — `LocationPolicy`
- `app/policies/location_scopes.rb` — `LocationPolicy::CourseScope`
- `app/policies/account_policy.rb` — `AccountPolicy` (`#summary` + `#capabilities` + `#index_summary`)
- `app/policies/account_scopes.rb` — `AccountPolicy::AdminScope`
- `app/policies/attendance_policy.rb` — `AttendancePolicy`
- `app/policies/attendance_scopes.rb` — `AttendancePolicy::EventScope` + `AttendancePolicy::EligibleScope` (renamed from `ListEligibleEvents`)
- `app/policies/enrollment_policy.rb` — `EnrollmentPolicy` (no scope — write-gate-only)
- `app/policies/system_role_policy.rb` — `SystemRolePolicy` (no scope — write-gate-only)
- `app/models/role.rb` — instance predicates (`admin?`, `creator?`, `teaching?`, etc.)
- Service refactor: `CreateCourseForOwner`, `EnrollAccountInCourse`, `AssignSystemRole`, `RecordAttendance` all drop inline role checks for policy reads
- `app/services/list_eligible_events.rb` — **deleted**; body relocated into `AttendancePolicy::EligibleScope`; callers updated
- Route refactor: `courses.rb` drops `Enrollment.first(...)` existence checks; `accounts.rb` drops inline admin check; `attendances.rb` uses `EligibleScope`
- Every read envelope carries `policies` key (full `#summary` on single, slim `#index_summary` on index)
- Self-Account envelope additionally carries `capabilities` key (actor-scoped predicates)
- Per-policy unit specs + per-scope unit specs (with scope ↔ policy consistency cross-check) + integration spec updates
- Small service-signature touchup folded in: tighten any caller that was passing a hydrated model to pass just the FK id — for these services this is mostly already done

**Out of scope** (deferred to later branches):

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

- [ ] `app/policies/course_policy.rb`: `CoursePolicy(account, course)` with `can_view?` / `can_edit?` / `can_delete?` / `can_enroll?` / `can_record_attendance?`; private helpers (`account_is_enrolled?`, `account_is_owner?`, `account_is_teaching_staff?`, `account_is_admin?`). Ships `#summary` (full) and `#index_summary` (slim — `{can_view, can_edit}`). **Per D4: no `can_create?` predicate on `CoursePolicy`** — course-creation is actor-scoped and lives on `AccountPolicy#can_create_course?`. `account_is_course_creator?` helper also removed (no remaining caller).
- [ ] `app/policies/course_scopes.rb`: `CoursePolicy::AccountScope(current_account, target_account=nil)` with `#viewable` (own enrollments + admin override). Class reopens across files for namespace nesting.
- [ ] `app/policies/event_policy.rb`: `EventPolicy` (CRUD: teaching staff; view: enrolled). `#summary` returns `{can_view, can_edit, can_delete, can_record_attendance}`. `#index_summary`: `{can_view, can_edit, can_record_attendance}`.
- [ ] `app/policies/event_scopes.rb`: `EventPolicy::CourseScope` — composes with `CoursePolicy::AccountScope` rather than re-deriving course visibility.
- [ ] `app/policies/location_policy.rb`: `LocationPolicy` (CRUD: teaching staff; view: enrolled). `#summary` returns `{can_view, can_edit, can_delete}`. `#index_summary`: `{can_view, can_edit}`.
- [ ] `app/policies/location_scopes.rb`: `LocationPolicy::CourseScope` (composes with `CoursePolicy::AccountScope`).
- [ ] `app/policies/account_policy.rb`: `AccountPolicy` with `initialize(viewer, target = viewer)` and **two surfaces**, **plus actor-scoped predicates per D4**:
  - **Actor-scoped predicates** (use `@viewer`; rule-owners — no cross-policy delegation):
    - `is_admin?` — `@viewer.system_roles.any?(&:admin?)`
    - `can_create_course?` — `@viewer.system_roles.any?(&:course_creator?)`
    - `can_manage_system_roles?` — delegates to `is_admin?`
  - **Entity-scoped predicates** (use `@target`): `can_view?`, `can_edit?`, `can_delete?`, `can_assign_role?`, `can_revoke_role?`. Private helpers (`viewer_is_admin?` — delegates to `is_admin?` —, `viewer_is_self?`).
  - `#summary` (entity-scoped) — `{can_view, can_edit, can_delete, can_assign_role, can_revoke_role}`. Runs for self and other; self viewing self → `can_edit: true`, `can_assign_role: false`; admin viewing other → management predicates true.
  - `#capabilities` (actor-scoped) — `{is_admin, can_create_course, can_manage_system_roles}`. **Self-referential per D4** — calls own predicates; no cross-policy delegation. Only emitted by the route when the envelope is the requesting actor's own account.
  - `#index_summary` — `{can_view, can_edit, can_assign_role}` for admin listings (per D1).
- [ ] `app/policies/account_scopes.rb`: `AccountPolicy::AdminScope#viewable` — admin sees all accounts; non-admin sees only self.
- [ ] `app/policies/attendance_policy.rb`: `AttendancePolicy` (record: enrolled student; view own: enrolled; manage: teaching staff). `#summary` returns `{can_view, can_record, can_manage}`. `#index_summary`: `{can_view}`.
- [ ] `app/policies/attendance_scopes.rb`: `AttendancePolicy::EventScope` (teaching staff sees all attendances for an event; students see only their own) + `AttendancePolicy::EligibleScope` (renamed from `ListEligibleEvents`; self-contained query — enrollment piece overlaps `CoursePolicy#can_view?`, time-window piece has no policy counterpart this branch).
- [ ] `app/policies/enrollment_policy.rb`: `EnrollmentPolicy` (manage: teaching staff in the course; leave: account owns the row except for `owner` role). `#summary` returns `{can_manage, can_leave}`. `#index_summary`: `{can_manage}`.
- [ ] `app/policies/system_role_policy.rb`: `SystemRolePolicy` (manage: admin only + per-target rules such as "can't revoke own admin role"). **Per D4: delegates the actor half to `AccountPolicy.new(@viewer).can_manage_system_roles?`**; this policy adds per-target constraints on top. `#summary` returns `{can_manage}`. No `#index_summary` (no listing route this branch).
- [ ] `require_app.rb`: add `'policies'` to default folders.

### Service refactor

- [ ] `app/services/create_course_for_owner.rb`: replace inline `intersect?(COURSE_CREATORS)` with `raise NotAuthorizedError unless AccountPolicy.new(current_account).can_create_course?` (per D4 — actor-scoped predicate on `AccountPolicy`, not `CoursePolicy`).
- [ ] `app/services/enroll_account_in_course.rb`: replace `TEACHING` check with `EnrollmentPolicy.new(current_account, course).can_manage?`.
- [ ] `app/services/assign_system_role.rb`: replace admin check with `SystemRolePolicy.new(current_account, target_account).can_manage?`.
- [ ] `app/services/record_attendance.rb`: replace student check with `AttendancePolicy.new(current_account, event).can_record?`.
- [ ] `app/services/list_eligible_events.rb`: **delete outright**. Body moves into `AttendancePolicy::EligibleScope` (in `app/policies/attendance_scopes.rb`). Callers (`app/controllers/attendances.rb`'s `GET /attendances/eligible`) update to `AttendancePolicy::EligibleScope.new(current_account).events`.

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

- [ ] Read routes merge `policies` into the envelope. Avoid putting policy into the model — the model doesn't know who's asking.
- [ ] **Single-resource reads** (`GET /courses/:id`, `GET /events/:id`, `GET /locations/:id`, `GET /accounts/:username`): merge `policies: XPolicy.new(current_account, resource).summary` (full shape).
- [ ] **Index reads** (`GET /courses`, `GET /courses/:id/events`, `GET /courses/:id/locations`, `GET /courses/:id/enrollments`, `GET /courses/:id/attendances`): map per resource, merging `policies: XPolicy.new(current_account, item).index_summary` (slim shape).
- [ ] **Self-Account envelope special case**: when `GET /accounts/:username` resolves to the requesting account (`current_account.username == username`), additionally merge `capabilities: AccountPolicy.new(current_account, current_account).capabilities`. Other-Account envelopes carry `policies` only.
- [ ] Events (`as_hash_for` from `6-auth-token`): merge `policies` into its output.

### Tests

- [ ] `spec/policies/course_policy_spec.rb`: HAPPY/SAD per predicate per role (owner, instructor, staff, student, enrolled-only, non-enrolled, admin). Cover both `#summary` (full) and `#index_summary` (slim) shapes.
- [ ] `spec/policies/course_scopes_spec.rb`: `AccountScope#viewable` — self returns enrolled courses; admin returns all; non-enrolled returns empty for foreign target. **Scope ↔ policy consistency cross-check**: iterate `AccountScope.new(account).viewable`; assert `CoursePolicy.new(account, course).can_view?` returns `true` for every result; iterate the complement (`Course.all` minus scope results); assert `can_view?` returns `false` for each. Catches drift between the SQL filter and the predicate.
- [ ] `spec/policies/event_policy_spec.rb`, `location_policy_spec.rb`, `attendance_policy_spec.rb`, `enrollment_policy_spec.rb`, `system_role_policy_spec.rb`: same pattern (per-predicate per-role; `#summary` + `#index_summary` shapes).
- [ ] `spec/policies/account_policy_spec.rb`: both surfaces. `#summary` cases: self viewing self / admin viewing other / non-admin viewing other. `#capabilities` cases (**rule-owners on `AccountPolicy` per D4**): admin → `is_admin: true`, `can_create_course: true`, `can_manage_system_roles: true`; member → all false; creator → `can_create_course: true` but others false. Predicates are tested directly (no cross-policy delegation to assert). `SystemRolePolicy#can_manage?(target)` is tested separately in `system_role_policy_spec.rb` for its per-target rules; that spec also cross-checks that `SystemRolePolicy#can_manage?` correctly short-circuits when `AccountPolicy#can_manage_system_roles?` returns false (stub the latter to assert the delegation).
- [ ] `spec/policies/event_scopes_spec.rb`, `location_scopes_spec.rb`, `account_scopes_spec.rb`: per-scope query coverage + scope ↔ policy cross-check pattern.
- [ ] `spec/policies/attendance_scopes_spec.rb`: covers `EventScope` (full cross-check via `AttendancePolicy#can_view?`) and `EligibleScope` (**partial cross-check** — assert each result's course passes `CoursePolicy#can_view?` for the enrollment piece; time-window piece has no policy counterpart this branch, so test it directly against `Time.now` fixtures).
- [ ] Update `spec/integration/api_courses_spec.rb`: assert full `policies` on `GET /courses/:id` and slim `policies` per row on `GET /courses`; assert 403 wiring on edit/delete by non-owner.
- [ ] Update `spec/integration/api_accounts_spec.rb`: assert self-Account response carries both `policies` + `capabilities` keys; assert other-Account response carries `policies` only (no `capabilities` leakage). 403 paths stay green.
- [ ] Update `spec/integration/api_attendances_spec.rb`, `api_enrollments_spec.rb`: 403 paths stay green; same external behavior.
- [ ] Update service specs: same `NotAuthorizedError` assertions, now raised by policy.

### Verify

- [ ] `bundle exec rake spec` green
- [ ] `bundle exec rubocop .` green
- [ ] `bundle exec bundle-audit check --update` green
- [ ] Manual smoke test: API on :3000, hit `GET /api/v1/courses/<id>` with a student Bearer token → response carries `policies.can_edit: false, can_record_attendance: true`. As owner → `can_edit: true`.
- [ ] Code review
- [ ] Diff review against the reference branch (`git show --name-status` + full-tree + shared-file content diff)
- [ ] Single payload commit shaped
- [ ] Merge PR to `main` — deferred to user

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

- **Smoke test (2026-05-21)** surfaced two additional inline-role-check smells that were within scope of this branch but missed in the original plan's four-canonical-extractions list: `CreateEventForCourse` and `CreateLocationForCourse` both carried `current_role.intersect?(Role::TEACHING)` with `# NOTE: role-checking belongs in a Policy object (see branch 7-policies)` TODO comments. Both refactored to `CoursePolicy.new(current_account, course).can_edit?` — the same predicate the App-side button-visibility uses, so UI and enforcement now agree. Total extractions on this branch: **six** (four canonical + these two). Lecture deck stays at the four named extractions for slide-story compactness.
- See `baby_tyto/.claude/plans/PLAN.api.7-policies.md` Post-Implementation Notes for the full reviewer pickup list.

---

Last updated: 2026-05-21 (plan created; Q1–Q5 + D1–D6 resolved — per-policy `#index_summary` table; actor-scoped predicates on `AccountPolicy` not `CoursePolicy`; capabilities-formalization + scope/policy-consistency slides land in week 13. Planning-repo plan at `baby_tyto/.claude/plans/PLAN.api.7-policies.md` is the canonical source for Q/D resolutions and deck update notes.)
