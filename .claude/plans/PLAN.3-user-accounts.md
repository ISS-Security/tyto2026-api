# 3-user-accounts — Account model with secure credentials, role join tables, enrollments

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update this plan before and after task and subtask implementations.

## Branch

`3-user-accounts`

## Goal

Introduce **Accounts** as a first-class persisted resource. This branch adds the `accounts` table, an `Account` Sequel model with secure password digestion (SCrypt via a `KeyStretch` library), and an HMAC-keyed email-lookup column so encrypted emails can still be queried. It also lays down the role-association data model: a `roles` reference table joined to accounts via `account_roles` (system-level roles: admin / creator / member), and an `enrollments` table joining accounts to courses with a `role_id` for the four course-level roles (owner / instructor / staff / student).

Course ownership is **derived** from enrollments — `Course#owner` returns the account whose enrollment for the course has role `owner`. There is no `owner_id` foreign key on the courses table.

`CreateCourseForOwner` is a transactional service that creates the course and its owner enrollment atomically. Two further service objects (`CreateEventForCourse`, `CreateLocationForCourse`) replace inline `course.add_event` / `course.add_location` calls in the controller so the service layer becomes the single seam for future policy enforcement.

Account routes (`POST api/v1/accounts`, `GET api/v1/accounts/[username]`) and enrollment-management routes (`GET`/`POST` on `/api/v1/courses/[course_id]/enrollments`, `DELETE` on `/api/v1/courses/[course_id]/enrollments/[enrollment_id]`) ship this week. The enrollment routes are intentionally **ungated** — consistent with the courses / events / locations routes that also trust the client at this stage. Authentication of credentials at the HTTP layer and the role-based policy gates that decide **who** may POST/DELETE enrollments are deferred to later branches.

## Strategy: Vertical Slice

1. Extend `SecureDB` with a keyed-hash method (HMAC-SHA256 using a separate `HASH_KEY`); add `KeyStretch` for SCrypt password hashing.
2. Renumber existing migrations (courses → 002, locations → 003, events → 004) and add new migrations (accounts → 001, roles → 005, account_roles → 006, enrollments → 007). The pre-production schema-rebuild posture (master plan §Decisions #10) makes this clean: dev/test SQLite databases are dropped and re-migrated; no `alter_table` migrations needed pre-`5-deployable`.
3. Build `Account`, `Password`, `Role`, `Enrollment` models. Add `Course#owner`, `Course#instructors`, `Course#staff`, `Course#students` convenience accessors over `enrollments` (no role-blind `#members` — every call site is role-aware).
4. Introduce service objects: `CreateCourseForOwner` (transactional — course + owner enrollment), `CreateEventForCourse`, `CreateLocationForCourse`.
5. Add account routes; refactor course/event/location POST handlers to call the new services.
6. Unit specs for `Password` (Mandarin UTF-8 round-trip included from the start — the `force_encoding` fix already landed in the prior database-hardening branch); integration specs for account routes; service-integration spec for `CreateCourseForOwner` (commit 2).

## Current State

- [x] Plan created
- [x] Branch `3-user-accounts` created off `main`
- [x] `CLAUDE.local.md` repointed at this plan
- [x] Plan file committed (`docs: plan 3-user-accounts`, `c830b52`)
- [ ] **Commit 1** — `Adds Accounts with credentials to DB, models, and routes` (Mandarin UTF-8 regression test included from the start — the `force_encoding` fix already landed in the prior database-hardening branch, so no separate fix commit to mirror)
- [ ] **Commit 2** — `Add service integration test`
- [ ] `bundle exec rake spec` green
- [ ] `bundle exec rubocop .` green
- [ ] `bundle exec bundle audit check --update` green
- [ ] Code review
- [ ] Retrospective migration audit (diff-level + full-tree + shared-file content diff)
- [ ] Merge PR to `main`

## Key Findings

### Starting point

- Domain on disk: `Course`, `Event`, `Location`. No `Account`, no `Role`, no `Enrollment`.
- `app/lib/secure_db.rb` already has `setup(base_key)`, `encrypt`, `decrypt` (with `.force_encoding(Encoding::UTF_8)` already applied in `2-db-hardening`). Needs to grow `hash(plaintext)` using `RbNaCl::HMAC::SHA256.auth` plus a separate key.
- `config/environments.rb` reads `DB_KEY` via `ENV.delete('DB_KEY')`. A sibling `ENV.delete('HASH_KEY')` is needed; `SecureDB.setup` will take both keys.
- `config/secrets-example.yml` and the `Rakefile`'s `newkey:db` task need siblings for `HASH_KEY` / `newkey:hash`.
- `require_app.rb` autoloads `%w[lib models controllers]`. Needs `services` added.
- `spec/spec_helper.rb`'s `wipe_database` resets events/locations/courses; needs to also clear `enrollments`, `account_roles`, `accounts` (children-first).
- `spec/env_spec.rb` (regression test that secrets are deleted from `ENV` after Figaro loads them) needs `HASH_KEY` added.
- Migrations on disk: `001_courses_create.rb`, `002_locations_create.rb`, `003_events_create.rb`. These will be renumbered (use `git mv` to keep `git log --follow` working).

### Threat model delta

| Risk | Addressed here | Deferred per project rules |
|---|---|---|
| Plaintext password storage | ✅ SCrypt-hashed via `KeyStretch` and a `Password` value object | Argon2 / future hash migration |
| GPU/ASIC password cracking at scale | ✅ SCrypt sequential-memory-hardness (`opslimit=2**20`, `memlimit=2**24`, `digest_size=64`) | Pepper |
| Email harvesting from a stolen DB dump | ✅ `email_secure` (SimpleBox encrypted, non-deterministic) | Email re-encryption rotation |
| No way to look up accounts by encrypted email | ✅ `email_hash` (HMAC-SHA256 with separate `HASH_KEY`) | Case/normalization on hash input |
| Single-key compromise exposes both confidentiality and lookup | ✅ Separate `HASH_KEY` and `DB_KEY` | Key rotation policy |
| Mass-assignment of internal account columns | ✅ `whitelist_security` allows only `:username, :email, :password, :avatar` | — |
| Password leakage through API serialization | ✅ `Account#to_json` returns `{type, id, username, email}` only | — |
| Mass-assignment of `Enrollment` rows (e.g., self-promotion student → owner) | ✅ `Enrollment` has `whitelist_security` allowing only `:account_id, :course_id, :role_id`; the enrollment POST route extracts `{username, role_name}` and calls `EnrollAccountInCourse` rather than mass-assigning directly. | **Who** may call the enrollment routes (role-based policy gating) lands in a later branch; this week any client can POST/DELETE, consistent with the other resource routes. |
| Course-creation race (course exists but no owner enrollment) | ✅ `CreateCourseForOwner` wraps both inserts in a Sequel transaction; spec covers rollback | — |
| Denormalized ownership (Credence's `owner_id` FK + collaborators join could disagree) | ✅ Single `enrollments` table is the only source of truth | — |
| Authentication of credentials at the HTTP layer | ❌ Deferred | — |
| Authorization (who can read/modify a course or its enrollments) | ⚠️ Partial — the **data model** lands here; the **enforcement** (Policy objects, route gates) is deferred | — |
| Server log leakage of passwords | Controllers log only `keys` of mass-assigned data; Roda's default logger does not log request bodies. Verbal lecture point: never `puts new_data` after `JSON.parse`. | Structured log redaction |

### Domain scope (this branch)

**New entities:**

- `Account` — `id`, `username` (unique), `email_secure`, `email_hash` (unique), `password_digest`, `avatar`, timestamps. Provides `email=` (sets both `email_secure` via SimpleBox and `email_hash` via HMAC), `email` (decrypts `email_secure`), `password=` (sets `password_digest` via `Password.digest(...).to_s`), `password?(try)`. Whitelist allows only `:username, :email, :password, :avatar`. Associations: `one_to_many :enrollments`, `many_to_many :system_roles, ..., :join_table: :account_roles`, `many_to_many :courses, join_table: :enrollments`. Convenience: `#owned_courses` (enrollments where role is `owner`).
- `Password` — value object with `(salt, digest)`. `Password.digest(plaintext) → Password`, `Password.from_digest(json_str) → Password`, `#correct?(try)`. `#to_s` is JSON `{salt, hash}`.
- `Role` — `id`, `name`. Static reference. Seeded with all seven role names. `many_to_many :accounts, join_table: :account_roles`; `one_to_many :enrollments`.
- `Enrollment` — `id`, `account_id` (FK, NOT NULL), `course_id` (FK, NOT NULL), `role_id` (FK, NOT NULL), timestamps. **Unique constraint at the DB level on `[account_id, course_id, role_id]`** so duplicate triples cannot be inserted by any code path (services, seeds, raw SQL, future routes). `many_to_one :account`, `many_to_one :course`, `many_to_one :role`. No `whitelist_security` — only services and seeds create rows. No spec asserts these DB invariants — that's the point of putting them in the schema. Behavioral tests for multi-role / duplicate prevention / ownerless-course belong in a later branch where policy code makes those invariants observable.

**Existing entities, modified:**

- `Course` — gains `one_to_many :enrollments`, `plugin :association_dependencies, enrollments: :delete` (alongside existing `events: :destroy, locations: :destroy`). **No `many_to_many :members`** — role-specific scopes carry all role-aware access; a role-blind members list has no caller. `enrollments: :delete` on course destruction is a 1-query bulk DELETE (no per-row `.destroy`; `Enrollment` has no hooks). Convenience scopes: `Course#owner` returns the account whose enrollment has role `owner`; `Course#instructors`, `Course#staff`, `Course#students` return arrays of accounts. **No `owner_id` column** — owner is derived.

**New library modules:**

- `KeyStretch` (mixin) — `new_salt`, `password_hash(salt, password)`. Used by `Password.digest`.

**Extended library modules:**

- `SecureDB` — gains `self.hash(plaintext)` returning Base64-encoded HMAC-SHA256 digest using `@hash_key`. `setup` now takes `(db_key, hash_key)`. New `NoHashKeyError`. Existing `encrypt`/`decrypt` unchanged.

**New services:**

- `CreateCourseForOwner.call(owner_id:, course_data:)` — transactional (`Tyto::Api.DB.transaction`):
  1. find the account; raise `UnknownOwnerError` if not found (caller-friendly error class)
  2. find the `owner` role (no custom error — if missing, the `Enrollment.create` below hits the DB NOT NULL on `role_id` and Sequel raises naturally; "use DB constraints where obvious")
  3. `Course.create(course_data)`
  4. `Enrollment.create(account_id:, course_id:, role_id:)`
  5. return the course
  Atomic — any failure rolls back both inserts.
- `EnrollAccountInCourse.call(account_id:, course_id:, role_name:)` — looks up the role by name and creates an `Enrollment`. Single seam for all non-owner enrollments (instructor / staff / student). Seeds use it this branch; enrollment-management routes will reuse it in `7-policies` when policy enforcement lands.
- `CreateEventForCourse.call(course_id:, event_data:)` — `Course.first(id: course_id).add_event(event_data)`
- `CreateLocationForCourse.call(course_id:, location_data:)` — `Course.first(id: course_id).add_location(location_data)`

**Migrations after this branch (renumbered + new):**

```text
db/migrations/
├── 001_accounts_create.rb           NEW
├── 002_courses_create.rb            renamed from 001 (no owner_id added)
├── 003_locations_create.rb          renamed from 002
├── 004_events_create.rb             renamed from 003
├── 005_roles_create.rb              NEW
├── 006_account_roles_create.rb      NEW (create_join_table)
└── 007_enrollments_create.rb        NEW (account_id + course_id + role_id, unique on the triple)
```

The dev/test SQLite databases get blown away and re-migrated as part of this branch. This is allowed pre-`5-deployable` per master plan §Decisions #10 (schema evolution): until production deployment, migrations may freely renumber, rename, drop columns, or restructure tables.

## Questions

> Strike through with the resolved decision once answered.

- [x] **Q1.** Add `owner_id` to courses now? → **No** (revised). Owner is derived from enrollments (`role = 'owner'`). Adding `owner_id` would duplicate the relationship and create a denormalization risk.
- [x] **Q2.** Add the per-course role join (`enrollments`) now? → **Yes** (revised). The lecture deck teaches the join-table pattern this week using a project↔collaborator example; `enrollments` is the right Tyto-shaped equivalent.
- [x] **Q3.** Seed `roles` with all seven names or only system-level three? → **All seven.** All seven are referenced this week — three by `account_roles`, four by `enrollments`.
- [x] **Q4.** Normalize email (lowercase/trim) before hashing? → **No**, deferred. Document as a deliberate design hole for the lecture.
- [x] **Q5.** Should `account.to_json` expose `email`? → **Yes**, but the integration spec must assert `salt`, `password`, `password_hash`, `email_secure`, and `email_hash` are absent.
- [x] **Q6.** `git mv` the renumbered migrations or rm+add? → **`git mv`** to preserve `git log --follow`.
- [x] **Q7.** Do we need `Course#owner` as a real method? → **Yes.** Tests, seeds, and (later) routes will call it. Implement once, in the model, with a Sequel dataset query against `enrollments`. Tested transitively via the service spec's HAPPY case (`course.owner == account`) — no separate unit test needed.
- [x] **Q8.** Does `Account` get an `add_owned_course` convenience method? → **No.** Without `one_to_many :owned_courses, key: :owner_id`, Sequel won't auto-generate it. The service object is the single seam.
- [x] **Q9.** Do we write specs for "duplicate triples are rejected" or "an account can hold multiple roles in the same course"? → **No** for this branch. These are DB invariants enforced by the unique constraint on `[account_id, course_id, role_id]` in the enrollments migration. The DB enforces; specs would just verify the constraint exists, which is framework-level testing. Behavioral tests of these invariants belong in the branch that adds policy logic with observable consequences.
- [x] **Q10.** Do we keep a custom error class for "owner role not found"? → **No.** If the `roles` seed is broken, `Role.first(name: 'owner')` returns nil and the subsequent `Enrollment.create(role_id: nil)` hits the DB NOT NULL constraint. The DB constraint *is* the enforcement; a custom exception is decoration that needs its own un-tested code path.
- [x] **Q12.** Ship enrollment-management routes this branch, or defer to the policy branch? → **Ship them this branch, intentionally ungated.** Rationale:
  - Consistency with courses/events/locations, which also accept un-authenticated writes at this stage.
  - Lets the future app exercise enrollments via HTTP without running seeds.
  - Cleaner pedagogical story for the policy branch: the routes already exist; that lecture introduces *gates*, not both routes and gates simultaneously. Same before/after pattern as `2-demo-db-vulnerabilities` → `2-db-hardening`.
  - `Enrollment` gains `whitelist_security` for defense-in-depth so any code path that directly mass-assigns to `Enrollment` can't set internal columns.

- [x] **Q11.** Now that `SecureDB` owns two keys (`@key` for encryption + `@hash_key` for HMAC lookup), should `@key` be renamed to disambiguate? → **No.** Credence's `6-auth-token` (three branches out) extracts the whole `@key` + `generate_key` + `base_encrypt` / `base_decrypt` triad into a `Securable` mixin that both `SecureDB` and `AuthToken` extend; the ivar then lives behind the mixin's memoized `key` accessor and `SecureDB` stops owning it directly. Renaming now would double the refactor cost and solve a naming ambiguity that disappears structurally when the mixin lands. Candidates considered: `@sym_key` (misleading — HMAC key is also symmetric), `@db_key` (best mirror of the `DB_KEY` env var), `@enc_key` (describes purpose) — all moot given the deferred refactor.

## Scope

**In scope:**

- `accounts` table with encrypted PII (`email_secure`, keyed-hash `email_hash`, `password_digest`)
- `roles` table seeded with all seven names + `account_roles` join (system-level) + `enrollments` join (per-course)
- `Account`, `Password`, `Role`, `Enrollment` models
- `Course#owner`, `Course#instructors`, `Course#staff`, `Course#students` convenience accessors over enrollments (no role-blind `#members` — every call site is role-aware)
- `Account#courses`, `Account#owned_courses` convenience accessors
- `KeyStretch` lib + extended `SecureDB` (HMAC method, `HASH_KEY` env var, `newkey:hash` Rake task)
- Four services: `CreateCourseForOwner` (transactional — course + owner enrollment), `EnrollAccountInCourse` (single seam for non-owner enrollments; seeds use it this branch, routes added in `7-policies`), `CreateEventForCourse`, `CreateLocationForCourse`
- Master seed file (`db/seeds/20260423_create_all.rb`) + `accounts_seed.yml` + `enrollments_seed.yml`
- Account routes: `POST api/v1/accounts`, `GET api/v1/accounts/[username]`
- **Enrollment routes (ungated):** `GET api/v1/courses/[course_id]/enrollments` (list), `POST api/v1/courses/[course_id]/enrollments` (create, body `{username, role_name}`), `DELETE api/v1/courses/[course_id]/enrollments/[enrollment_id]` (remove; validates enrollment belongs to the named course). `whitelist_security` on `Enrollment` blocks mass-assignment of internal columns. Role-based access control is deferred to a later branch.
- `plugin :all_verbs` added to the Roda app so `routing.delete` resolves as a verb matcher (Roda 3 ships only `get`/`post` by default).
- `passwords_spec.rb` (unit; Mandarin round-trip included from commit 1 — the `force_encoding` fix already lives in `SecureDB.decrypt` from the prior database-hardening branch, so there's no separate UTF-8-fix commit to mirror)
- `api_accounts_spec.rb` (integration)
- `service_create_course_for_owner_spec.rb` (integration, commit 2 — happy + transactional rollback)
- **No `enrollments_spec.rb`** — DB constraints (unique triple, NOT NULL FKs) enforce structural invariants directly; behavioral tests of those invariants belong in a later branch.
- README updates listing new routes
- Refactor course/event/location POST handlers to call the new services

**Out of scope** (deferred per project rules — do not creep in):

- Authentication route
- Encrypted/expiring auth tokens
- Authorization policies / policy objects
- Role-based policy gating for the enrollment routes (the routes themselves ship this branch, ungated — who may call them is enforced later)
- Attendance (table, model, routes)
- Email verification
- SSO
- Signed requests
- Pepper for password hashing
- Avatar file upload (column is a free-form String)
- Email normalization (lower/trim)
- `whitelist_security` on `Role` — the roles table is seed-only and not user-creatable
- `enrollments_spec.rb` — DB constraints enforce the invariants; behavioral tests deferred
- `MissingOwnerRoleError` custom exception in `CreateCourseForOwner` — DB NOT NULL on `enrollments.role_id` raises naturally if the seed is broken
- Tests of "ownerless course" behavior, multi-role-per-course, or duplicate-triple rejection — deferred

## Security Concerns Addressed This Week

1. **Plaintext password storage is unsafe** — passwords are stored as SCrypt digests via `Password` + `KeyStretch`. The plaintext is never persisted, never logged, never serialized. Validated by `passwords_spec.rb` and by `api_accounts_spec.rb` asserting `result['password']`/`result['password_hash']`/`result['salt']` are all `nil`.
2. **Brute-force resistance** — SCrypt parameters (`opslimit=2**20`, `memlimit=2**24`, `digest_size=64`) defeat GPU/ASIC parallelism via sequential-memory-hardness.
3. **Per-account salt** — defeats rainbow tables; identical passwords produce different digests across accounts.
4. **Email is PII** — encrypted at rest via `SecureDB.encrypt` (RbNaCl SimpleBox, non-deterministic ciphertext).
5. **Encrypted-but-searchable** — keyed-hash (HMAC-SHA256, `RbNaCl::HMAC::SHA256.auth(@hash_key, plaintext)`) on a *separate* `HASH_KEY` enables `WHERE email_hash = ?` lookup without exposing plaintext or being brute-forceable from a leaked DB alone.
6. **Key separation** — `DB_KEY` (confidentiality) and `HASH_KEY` (lookup) are distinct. Compromise of one doesn't compromise the other.
7. **Mass-assignment defense extended to accounts** — `whitelist_security` allows only `:username, :email, :password, :avatar`. Internal columns cannot be set from JSON. Verified by `api_accounts_spec.rb`.
8. **No password leakage through API serialization** — `Account#to_json` returns `{type, id, username, email}` only.
9. **Service objects encapsulate side-effects** — `CreateCourseForOwner` is the future hook point for authorization checks.
10. **Server log discipline** — controllers log only `keys` of mass-assigned data, never values; passwords never reach `Api.logger`.
11. **Atomic course-ownership creation** — `CreateCourseForOwner` wraps the course insert and the owner-enrollment insert in a Sequel transaction. Without this, a database hiccup could leave a course with no owner — silently denying anyone the right to manage it once policy enforcement lands. Spec asserts no Course row remains after a forced rollback.
12. **Single source of truth for "who has what role on what course"** — the `enrollments` table is the only place this lives. Lecture moment: the security model is only as strong as its data model; when policies arrive in a future branch, every check reads from this one table.
13. **Database constraints as the authoritative enforcement layer** — `enrollments` has a unique constraint on `[account_id, course_id, role_id]` and NOT NULL on every FK. `accounts.username` and `accounts.email_hash` are unique. `account_roles` (via `create_join_table`) has a composite primary key blocking duplicates. We do **not** write specs to verify these constraints exist — that would just verify the framework. Application code can rely on them (no defensive double-checks needed in services), and broken invariants surface as Sequel exceptions at the boundary. Project rule: use DB constraints where obvious; the database is the source of truth for structural invariants. Application code and policy logic only enforce *contextual* rules (e.g., "this user is a student, so they can only check in to events").

## Tasks

> Check tasks off as soon as each one is finished — do not batch.

### Plan-phase scaffolding

- [x] T01. Read reference branch + read `tyto2026-api/main` state
- [x] T02. Read week's lecture deck and synthesize themes
- [x] T03. Decide commit count (3) and grouping
- [x] T04. Write this plan
- [x] T05. `git checkout main`, then `git checkout -b 3-user-accounts`
- [x] T06. Repoint `CLAUDE.local.md` at this plan
- [x] T07. Commit only this plan: `git commit -m "docs: plan 3-user-accounts"`
### Commit 1 — `Adds Accounts with credentials to DB, models, and routes`

#### Setup

- [ ] T08. Add `gem 'sequel-seed'` to `Gemfile` (under `:development, :test`); `bundle install`
- [ ] T09. After T15: `bundle exec rake newkey:hash` and paste the value into `config/secrets.yml` for `development` and `test`. Never commit this file.

#### Crypto / lib

- [ ] T10. Create `app/lib/key_stretch.rb` (module `Tyto::KeyStretch`)
- [ ] T11. Extend `app/lib/secure_db.rb`: add `NoHashKeyError`, change `setup` to `setup(db_key, hash_key)`, store `@hash_key`, add `self.hash(plaintext)` returning `Base64.strict_encode64(RbNaCl::HMAC::SHA256.auth(@hash_key, plaintext))`
- [ ] T12. Extend `spec/unit/secure_db_spec.rb` with two tests: deterministic keyed hash for same input; different keyed hashes for different inputs

#### Config

- [ ] T13. Update `config/environments.rb`: `SecureDB.setup(ENV.delete('DB_KEY'), ENV.delete('HASH_KEY'))`
- [ ] T14. Update `config/secrets-example.yml`: add `HASH_KEY:` placeholder for `development`, `test`, `production`
- [ ] T15. Update `Rakefile`: add `newkey:hash` task (reuse `Tyto::SecureDB.generate_key`)
- [ ] T15a. Wire up seeding tasks in `Rakefile` per this week's lecture deck (slide 22 — students will run these):
  - Extend existing `db:load_models` to `require_app(%w[config models services])` (adding `services`) so seeders can call `CreateCourseForOwner` and `EnrollAccountInCourse`.
  - Add `task :reset_seeds => [:load_models]`: delete `@app.DB[:schema_seeds]` rows if the table exists; `Tyto::Account.dataset.destroy` (cascades via `association_dependencies`).
  - Add `desc 'Seeds the development database'; task :seed => [:load_models]` that `require 'sequel/extensions/seed'`, calls `Sequel::Seed.setup(:development)`, `Sequel.extension :seed`, `Sequel::Seeder.apply(@app.DB, 'db/seeds')`.
  - Add top-level `desc 'Delete all data and reseed'; task reseed: %i[db:reset_seeds db:seed]`.
- [ ] T16. Update `require_app.rb` default folders to `%w[lib models services controllers]`
- [ ] T17. Update `spec/env_spec.rb` to also assert `ENV['HASH_KEY']` is `nil` after boot

#### Schema

- [ ] T18. Create `db/migrations/001_accounts_create.rb` (`username` unique, `email_secure` non-null, `email_hash` non-null+unique, `password_digest`, `avatar`, timestamps)
- [ ] T19. `git mv db/migrations/001_courses_create.rb db/migrations/002_courses_create.rb` (**no body change** — no `owner_id`)
- [ ] T20. `git mv db/migrations/002_locations_create.rb db/migrations/003_locations_create.rb`
- [ ] T21. `git mv db/migrations/003_events_create.rb db/migrations/004_events_create.rb`
- [ ] T22. Create `db/migrations/005_roles_create.rb` (`primary_key :id`, `String :name, null: false, unique: true`, timestamps)
- [ ] T23. Create `db/migrations/006_account_roles_create.rb` using `create_join_table(account_id: :accounts, role_id: :roles)`
- [ ] T24. Create `db/migrations/007_enrollments_create.rb` — `primary_key :id`; `foreign_key :account_id, :accounts, null: false`; `foreign_key :course_id, :courses, null: false`; `foreign_key :role_id, :roles, null: false`; timestamps; `unique %i[account_id course_id role_id]`
- [ ] T25. Drop + re-migrate dev and test DBs (`bundle exec rake db:drop && bundle exec rake db:migrate`; same for `RACK_ENV=test`). Allowed pre-`5-deployable`.

#### Models

- [ ] T26. Create `app/models/password.rb` (value object, `extend KeyStretch`, namespaced `Tyto::Password`)
- [ ] T27. Create `app/models/account.rb`:
  - `one_to_many :enrollments`
  - `many_to_many :system_roles, class: :'Tyto::Role', join_table: :account_roles`
  - `many_to_many :courses, join_table: :enrollments`
  - `plugin :association_dependencies, courses: :nullify` — on a `many_to_many`, `:nullify` removes the join-table rows (1 bulk DELETE) and leaves the courses standing. Chosen over `enrollments: :destroy` on the `one_to_many` (which would be N per-row `.destroy` calls) for both performance and intent match ("remove the bridges, keep both endpoints")
  - `plugin :whitelist_security; set_allowed_columns :username, :email, :password, :avatar`
  - `plugin :timestamps, update_on_create: true`
  - `email=`, `email`, `password=`, `password?(try)`
  - `def owned_courses; enrollments_dataset.where(role: Tyto::Role.first(name: 'owner')).map(&:course); end`
  - `to_json(opts) → {type, id, username, email}`
- [ ] T28. Create `app/models/role.rb` (`many_to_many :accounts, join_table: :account_roles`; `one_to_many :enrollments`; `to_json → {id, name}`)
- [ ] T29. Create `app/models/enrollment.rb` (`many_to_one :account`, `many_to_one :course`, `many_to_one :role`, timestamps; `to_json → {id, account_id, course_id, role: role.name}`)
- [ ] T30. Update `app/models/course.rb`:
  - add `one_to_many :enrollments`
  - **No** `many_to_many :members` — role-specific scopes cover every access site; a role-blind members list has no caller and adding it would let role-awareness sneak out of code paths
  - extend `plugin :association_dependencies` to include `enrollments: :delete` (bulk 1-query DELETE, no per-row `.destroy`; fine because `Enrollment` has no hooks)
  - add `Course#owner`, `Course#instructors`, `Course#staff`, `Course#students` convenience scopes
  - **Do not** add `owner_id` to whitelist (the column does not exist)

#### Services

- [ ] T31. Create `app/services/create_course_for_owner.rb` — transactional:

  ```ruby
  module Tyto
    class CreateCourseForOwner
      class UnknownOwnerError < StandardError; end

      def self.call(owner_id:, course_data:)
        Tyto::Api.DB.transaction do
          account    = Account.first(id: owner_id) or raise UnknownOwnerError
          owner_role = Role.first(name: 'owner')
          course     = Course.create(course_data)
          Enrollment.create(account_id: account.id, course_id: course.id, role_id: owner_role&.id)
          course
        end
      end
    end
  end
  ```

  Note: `owner_role&.id` deliberately produces `nil` if the `owner` role row is missing. The DB's NOT NULL on `enrollments.role_id` then raises and rolls back the transaction. The DB constraint is the enforcement; a custom exception class would be decoration.

- [ ] T31a. Create `app/services/enroll_account_in_course.rb`:

  ```ruby
  module Tyto
    class EnrollAccountInCourse
      class UnknownRoleError < StandardError; end

      def self.call(account_id:, course_id:, role_name:)
        role = Role.first(name: role_name) or raise(UnknownRoleError, role_name)
        Enrollment.create(account_id:, course_id:, role_id: role.id)
      end
    end
  end
  ```

  Single seam for non-owner enrollments. Seeds call this for all instructor / staff / student rows; enrollment-management routes that call this service land in `7-policies` alongside policy checks.
- [ ] T32. Create `app/services/create_event_for_course.rb` — `Course.first(id: course_id).add_event(event_data)`
- [ ] T33. Create `app/services/create_location_for_course.rb` — `Course.first(id: course_id).add_location(location_data)`
- [ ] T34. Refactor `app/controllers/app.rb` POST handlers for events and locations to call the new services. Leave POST `/courses` calling `Course.new(...)` directly for now (no owner context yet — the route does NOT call `CreateCourseForOwner` because there's no authenticated account to use as owner; that wiring lands in the next branch).

#### Controllers

- [ ] T35. Add `routing.on 'accounts'` block (sibling to `routing.on 'courses'`):
  - `routing.on String do |username| routing.get { Account.first(username:)... }`
  - `routing.post do new_data = JSON.parse(routing.body.read); new_account = Account.new(new_data); raise unless new_account.save_changes; 201 + Location header end`
  - `rescue Sequel::MassAssignmentRestriction → 400`, `rescue StandardError → 500`
  - `Api.logger.warn "MASS-ASSIGNMENT: #{new_data.keys}"` (keys only, never values)
- [ ] T35a. Add `plugin :all_verbs` to the `Api` class so `routing.delete` works as a verb matcher (Roda 3 ships only `get`/`post` matchers by default).
- [ ] T35b. Add `plugin :whitelist_security; set_allowed_columns :account_id, :course_id, :role_id` to `app/models/enrollment.rb`. Defense-in-depth — the enrollment POST route doesn't mass-assign, but this hardens any future code path that does.
- [ ] T35c. Extend the controller under `routing.on 'courses' do ... routing.on String do |course_id|`:
  - `routing.on 'enrollments' do`
    - `routing.get` (no args) → `{ data: Course.first(id: course_id).enrollments }`
    - `routing.post` → parse `{username, role_name}` from body; look up account by username (404 if unknown); call `EnrollAccountInCourse.call(account_id:, course_id:, role_name:)`; 201 + `Location` header pointing at `/api/v1/courses/:course_id/enrollments/:enrollment_id`
    - `routing.on String do |enrollment_id|` → `routing.delete`: fetch `Enrollment.first(id: enrollment_id)`, assert its `course_id` matches the URL's `course_id` (404 if not — prevents cross-course ID guessing), `.destroy`, return 200 + `{message: 'Enrollment removed'}`
  - Rescues: `Sequel::MassAssignmentRestriction` → 400 (+ `Api.logger.warn "MASS-ASSIGNMENT: #{new_data.keys}"`); `Tyto::EnrollAccountInCourse::UnknownRoleError` → 400; `Sequel::UniqueConstraintViolation` → 409; generic → 500

#### Seeds

- [ ] T36. Create `db/seeds/accounts_seed.yml` with **nine accounts** (3 staff + 6 students):

  ```yaml
  # Staff / faculty
  - username: soumya.ray
    email: soumya.ray@nthu.edu.tw
    password: change_me_soumya
  - username: jerry.ho
    email: jerry.ho@nthu.edu.tw
    password: change_me_jerry
  - username: galit
    email: galit@nthu.edu.tw
    password: change_me_galit
  # Students
  - username: li.wei
    email: li.wei@nthu.edu.tw
    password: student_pass_1
  - username: chen.hsinyi
    email: chen.hsinyi@nthu.edu.tw
    password: student_pass_2
  - username: wang.ting
    email: wang.ting@nthu.edu.tw
    password: student_pass_3
  - username: lin.chiahao
    email: lin.chiahao@nthu.edu.tw
    password: student_pass_4
  - username: huang.peijun
    email: huang.peijun@nthu.edu.tw
    password: student_pass_5
  - username: tsai.yuting
    email: tsai.yuting@nthu.edu.tw
    password: student_pass_6
  ```

  Passwords are placeholders; `Account.create` hashes them at seed time.

- [ ] T36a. **Replace existing `db/seeds/course_seeds.yml`** with four canonical courses:

  ```yaml
  - name: Service Oriented Architecture
    description: Architectural patterns for loosely-coupled, service-centric systems.
  - name: IT Service Security
    description: Security engineering for internet-facing IT services.
  - name: Computational Statistics
    description: Simulation-based statistical methods and data analysis.
  - name: Data Mining
    description: Methods and practice for extracting patterns from data.
  ```

  Placeholder names from `1-db-orm` get overwritten (allowed pre-production).

- [ ] T37. Create `db/seeds/enrollments_seed.yml` with explicit triples (13 rows):

  ```yaml
  # Owners
  - username: soumya.ray
    course_name: Service Oriented Architecture
    role_name: owner
  - username: soumya.ray
    course_name: IT Service Security
    role_name: owner
  - username: soumya.ray
    course_name: Computational Statistics
    role_name: owner
  - username: galit
    course_name: Data Mining
    role_name: owner
  # TA
  - username: jerry.ho
    course_name: IT Service Security
    role_name: staff
  # Students
  - username: li.wei
    course_name: Service Oriented Architecture
    role_name: student
  - username: li.wei
    course_name: IT Service Security
    role_name: student
  - username: chen.hsinyi
    course_name: IT Service Security
    role_name: student
  - username: chen.hsinyi
    course_name: Data Mining
    role_name: student
  - username: wang.ting
    course_name: Computational Statistics
    role_name: student
  - username: lin.chiahao
    course_name: Service Oriented Architecture
    role_name: student
  - username: huang.peijun
    course_name: Data Mining
    role_name: student
  - username: tsai.yuting
    course_name: Computational Statistics
    role_name: student
  ```

  Exercises `owner` (4 rows), `staff` (1 row), `student` (8 rows). Jerry.ho's only course enrollment is as TA (staff) of IT Service Security — she owns no course and instructs no course. `instructor` exists in the `roles` table but is not referenced by seeds this branch.

- [ ] T38. Create `db/seeds/20260423_create_all.rb` master seeder using `Sequel.seed(:development)`:
  1. Seed `roles` (all seven names: `admin`, `creator`, `member`, `owner`, `instructor`, `staff`, `student`) via `Role.find_or_create(name:)` — idempotent.
  2. Seed accounts via `Account.create` for each row in `accounts_seed.yml`.
  3. Assign **system roles** hardcoded in the seeder:
     - `soumya.ray` → `admin` + `creator`
     - `jerry.ho` → `admin` + `creator`
     - `galit` → `creator` (professor; empowered to create her own `Data Mining` course)
     - `li.wei`, `chen.hsinyi`, `wang.ting`, `lin.chiahao`, `huang.peijun`, `tsai.yuting` → `member`

     Use `account.add_system_role(role)`.
  4. For each `enrollments_seed.yml` row where `role_name == 'owner'`, call `CreateCourseForOwner.call(owner_id:, course_data:)` (looking up course attributes from `course_seeds.yml` by `course_name`).
  5. For each non-owner row, call `EnrollAccountInCourse.call(account_id:, course_id:, role_name:)` — no direct `Enrollment.create` in seeds.
  6. Seed locations from `location_seeds.yml` into courses by course name via `CreateLocationForCourse`.
  7. Seed events from `event_seeds.yml` into courses by course name (cycle courses via `Enumerable#cycle`) via `CreateEventForCourse`.
- [ ] T39. Keep the existing per-resource YAMLs (`location_seeds.yml`, `event_seeds.yml`) as data sources — the master file orchestrates rather than replaces.

#### Tests (commit 1)

- [ ] T40. Create `spec/unit/passwords_spec.rb` — three tests (digest hides raw, correct password matches, wrong password doesn't) using Mandarin-containing password `'secret password of 雷松亞 stored in db'` per the week's lecture deck. Namespaced `Tyto::Password`. The reference branch's separate UTF-8-fix commit is skipped here because the `force_encoding` fix already landed in the prior database-hardening branch; the regression guarantee lives in this spec from day one.
- [ ] T41. **Skipped** — no `spec/unit/enrollments_spec.rb` this branch. DB constraints (unique `[account_id, course_id, role_id]`, NOT NULL FKs) enforce the structural invariants; behavioral tests of multi-role / duplicate prevention / ownerless-course belong in a later branch where policy code makes them observable.
- [ ] T42. Create `spec/integration/api_accounts_spec.rb`:
  - `Account information / HAPPY: should be able to get details of a single account` (asserts no `salt`, `password`, `password_hash`, `email_secure`, `email_hash` in response)
  - `Account Creation / HAPPY: should be able to create new accounts` (201, Location header, `account.password?` verifies)
  - `Account Creation / BAD: should not create account with illegal attributes` (sends `created_at` → expects 400)
- [ ] T42a. Create `spec/integration/api_enrollments_spec.rb`:
  - `Listing enrollments / HAPPY: should list enrollments for a course`
  - `Creating enrollments / HAPPY: should create a student enrollment` (201, Location header, `course.students` includes the account)
  - `Creating enrollments / SAD: should 404 on unknown username`
  - `Creating enrollments / SAD: should 400 on unknown role_name` (Tyto::EnrollAccountInCourse::UnknownRoleError)
  - `Creating enrollments / SAD: should 409 on duplicate (account, course, role) triple` (exercises the DB unique constraint surfacing as HTTP 409)
  - `Deleting enrollments / HAPPY: should remove an enrollment`
  - `Deleting enrollments / SAD: should 404 when enrollment_id belongs to a different course` (guards against cross-course ID guessing)
  - `Deleting enrollments / SAD: should 404 for nonexistent enrollment_id`
  - `Mass-assignment defense / SECURITY: whitelist_security blocks setting internal columns` — asserts `Tyto::Enrollment.new(created_at: '1900-01-01', ...)` raises `Sequel::MassAssignmentRestriction`
- [ ] T43. Update `spec/spec_helper.rb`: extend `wipe_database` to delete `enrollments`, `account_roles`, `accounts` (children-first); load `DATA[:accounts]` from `accounts_seed.yml`; load `DATA[:enrollments]` from `enrollments_seed.yml`
- [ ] T44. Confirm `spec/integration/api_courses_spec.rb` still passes

#### Verify (commit 1)

- [ ] T45. `bundle exec rake spec` — green
- [ ] T46. `bundle exec rubocop .` — green
- [ ] T47. `bundle exec bundle audit check --update` — green
- [ ] T48. Stage **only** the files for commit 1 (no `git add -A`); double-check `config/secrets.yml` and `db/local/*.db` are not staged
- [ ] T49. `git commit -m "Adds Accounts with credentials to DB, models, and routes"` (subject verbatim; body lists files added/changed and the security guarantees, and notes that enrollments were pulled forward per project schema-evolution policy)

### Commit 2 — `Add service integration test`

- [ ] T50. Create `spec/integration/service_create_course_for_owner_spec.rb` (HAPPY + one SAD, mirrors the reference branch's two-test shape):
  - `before`: `wipe_database` + seed `roles` + create one account
  - `HAPPY: should create a course AND an owner enrollment atomically` (assert both rows exist; assert `course.owner == account` — transitively covers `Course#owner` and basic `Enrollment` association)
  - `SAD: should raise UnknownOwnerError when owner_id is unknown AND roll back any Course row` (proves the transaction wraps both inserts — the only meaningful security assertion in this commit)
- [ ] T51. (If not already done in T16) ensure `require_app.rb` autoloads `services`
- [ ] T52. `bundle exec rake spec` — green
- [ ] T53. `bundle exec rubocop .` — green
- [ ] T54. `git commit -m "Add service integration test"` (subject verbatim)

### Verify (whole branch)

- [ ] T55. `bundle exec rake release_check` (spec + style + audit) — green end-to-end (task is already wired up in the Rakefile from the prior database-hardening branch)
- [ ] T56. Code review
- [ ] T57. Retrospective migration audit (diff-level + full-tree + shared-file content diff vs the reference branch). The `enrollments` migration + model + spec are Tyto-only adds; flag them in the audit narrative as deliberate adaptations per project schema-evolution policy. Also flag the deliberate skip of the reference branch's middle (UTF-8-fix) commit — its fix already landed in the prior database-hardening branch; the regression test is folded into commit 1.
- [ ] T58. Open PR
- [ ] T59. Merge PR to `main`
- [ ] T60. Skill self-reflection — re-read `/week-plan` SKILL.md and propose refinements if any

## Commit strategy

- **Required commit count**: **2** (the reference branch had 3; the middle UTF-8-fix commit is skipped — its fix already shipped in the prior database-hardening branch)
- **Mapping**:

  | Tyto commit # | Subject (verbatim from reference) |
  |---|---|
  | 1 | `Adds Accounts with credentials to DB, models, and routes` |
  | — | *Skipped — `Pass tests for decrypting encrypted UTF-8 characters outside ASCII range`. Fix already in prior branch; regression test folded into commit 1's `passwords_spec.rb`.* |
  | 2 | `Add service integration test` |

- The plan commit (`docs: plan 3-user-accounts`) does **not** count toward the payload total.
- **Body content (commit 1)**: list of new files, renumbered migrations, modified files, and a one-paragraph "what this delivers" — accounts CRUD + secure password storage + email-as-PII pattern + service-object pattern + role-association data model. Briefly mention the schema-evolution policy that allowed the renumbering, and that the reference branch's intermediate UTF-8-fix commit is skipped because the fix already landed in the prior database-hardening branch (regression test lives in this commit's `passwords_spec.rb`).

## Completed

(filled in during finalize)

## Post-Implementation Notes (for reviewer)

(filled in before handing off for review)

---

Last updated: 2026-04-23
