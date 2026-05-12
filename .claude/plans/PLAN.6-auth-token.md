# 6-auth-token — Token-based authorization and registration verification

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update this plan before and after task and subtask implementations.

## Branch

`6-auth-token`

## Goal

Replace the API's open authorization model — currently every authenticated route trusts a `current_account_id` field sent by the client — with **encrypted Bearer tokens** issued by `POST /auth/authenticate`. The token is the API's only source of identity. Pair this with **email-verified registration**: a new `POST /auth/register` endpoint sends a SendGrid email containing a verification URL that the user must click before their account can materialize.

Three coupled pieces ship together:

1. A reusable cryptographic primitives mixin (`Securable`) extracted from `SecureDB`, plus a sibling `AuthToken` library that issues and parses time-limited encrypted tokens.
2. `POST /auth/authenticate` now wraps its response in an `{account, auth_token}` envelope; every protected route reads `@auth_account` from the Bearer header.
3. `POST /auth/register` calls a new `VerifyRegistration` service that sends a SendGrid email containing the App's verification URL.

## Strategy: Vertical Slice

Order the work so each layer compiles before the next.

1. **Crypto refactor** — Extract `Securable` from `SecureDB`. Keep `SecureDB.hash` (HMAC keyed lookup) on `SecureDB` because the encrypted-email pattern depends on it. Add `AuthToken` extending `Securable`.
2. **Config + boot** — `MSG_KEY` env var, `AuthToken.setup` in `environments.rb`, `newkey:msg` rake task, secrets-example additions.
3. **Authentication envelope** — `AuthenticateAccount` returns `{type: 'authenticated_account', attributes: {account: <envelope>, auth_token: <string>}}`. Spec assertions follow.
4. **Bearer plumbing** — `HttpRequest#authenticated_account` reads the Authorization header → `AuthToken.new(token).payload` → returns the account attributes hash. `app.rb` populates `@auth_account` once per request; rescues `AuthToken::InvalidTokenError` → 403.
5. **Route refactor** — `courses.rb` and `accounts.rb` drop `current_account_id` from query params and body; switch to `@auth_account['attributes']['id']`. `POST /accounts` stays open.
6. **Registration flow** — `VerifyRegistration` service (SendGrid HTTP call). `POST /auth/register` route returns 202 after the email is sent. The actual `POST /accounts` (password set) is unchanged.
7. **Tests** — Update existing auth + course + account specs for the new envelope and Bearer header; add lib spec for `AuthToken` and service spec for `AuthenticateAccount`.

## Current State

- [ ] Plan created
- [ ] Branch `6-auth-token` created off `main`
- [ ] Crypto refactor: `Securable` extracted, `SecureDB` slimmed, `AuthToken` added
- [ ] Config + Rakefile: `MSG_KEY` wired, `newkey:msg` added, `secrets-example.yml` updated
- [ ] `AuthenticateAccount` returns token envelope
- [ ] Bearer extraction in `HttpRequest` + `app.rb`
- [ ] `courses.rb` switched to `@auth_account`
- [ ] `accounts.rb` switched to `@auth_account` (POST stays open; system-role routes refactored)
- [ ] `VerifyRegistration` service implemented
- [ ] `POST /auth/register` route added
- [ ] Tests updated / added (Payload 1)
- [ ] Attendance: migration, `Attendance` model, `RecordAttendance` + `ListEligibleEvents` services, three course-nested routes + top-level eligible route, `Event#to_json` carries `my_attendance_id`
- [ ] Attendance tests
- [ ] `rake spec` green
- [ ] `bundle exec rubocop .` green
- [ ] `bundle audit check --update` green
- [ ] Retrospective migration audit
- [ ] Squash to 2 payload commits (token-auth + attendance)
- [ ] Merge PR to `main` — deferred to user

## Key Findings

### Starting point

- `SecureDB` is monolithic: `setup(db_key, hash_key)`; methods are `encrypt`, `decrypt`, and `hash` (HMAC-SHA256 keyed). This is richer than the reference template's pre-branch `SecureDB`; the refactor must keep the `hash` method on `SecureDB` while extracting the symmetric-encryption primitives into `Securable`.
- `AuthenticateAccount` returns the bare `Account` Sequel model; the auth route just `to_json`s it. After this branch, the service returns the new envelope.
- `app.rb` does not parse any Authorization header today. `@auth_account` does not exist yet.
- `courses.rb` and `accounts.rb` read `current_account_id` from request params (GET) or body (POST/PUT/DELETE). This is the pattern being replaced.
- `newkey:db` and `newkey:hash` rake tasks exist; `newkey:msg` is missing.
- No `http` gem in Gemfile (needed for SendGrid). No `webmock` in test group.
- `Account` model has `email=` that writes both `email_secure` and `email_hash`. No class method exists for email lookup — `VerifyRegistration#email_available?` must query `Account.first(email_hash: SecureDB.hash(plaintext))` inline.

### Threat model delta

| Risk | Addressed here | Deferred |
| --- | --- | --- |
| API trusts client-supplied `current_account_id` | Replaced with encrypted Bearer-token-derived `@auth_account` | Per-route policy gates (deferred per project rules) |
| Plaintext account registration over the wire | Email verification gates account creation — only someone who can read the email can complete the password-set step | Server-side rate limiting on `/auth/register` (deferred) |
| Token replay after compromise | Tokens are time-limited (default `ONE_WEEK`) and encrypted with `MSG_KEY` | Token revocation list (deferred) |
| Email verification token tampering | Token is `SimpleBox`-encrypted (XSalsa20-Poly1305 AEAD): forgery requires `MSG_KEY` | — |

### Domain scope

No new entities. Existing entities (Account, Course, Event, Location, Enrollment) keep their schemas. The change is at the controller boundary: the API stops trusting `current_account_id` query params / body fields and starts trusting only the encrypted Bearer token.

### Notes on the refactor

- **`Securable` mixin** provides `generate_key`, `setup(base_key)`, `key`, `base_encrypt(plaintext)`, `base_decrypt(ciphertext)` — pure RbNaCl SimpleBox primitives. `SecureDB.extend Securable`, then override `setup(db_key, hash_key)` to call `super(db_key)` and store `@hash_key` separately. `AuthToken.extend Securable` only — its setup takes a single `MSG_KEY`.
- **Token payload**: pass the full `Account#to_json` envelope to `AuthToken.create(account, AuthToken::ONE_WEEK)`. The encrypted payload carries `{type, attributes: {id, username, email}, include: {system_roles, enrollments}}`. The `@auth_account` reconstituted from the Bearer header has `attributes['id']`, `include['system_roles']`, `include['enrollments']` — everything every authenticated route needs.
- **`POST /accounts` stays open**. Other routes that previously took `current_account_id` get refactored to read `@auth_account['attributes']['id']` and return 401 if `@auth_account` is nil.
- **Inline role checks stay scattered**. `CreateCourseForOwner`, `EnrollAccountInCourse`, `AssignSystemRole`, and the inline `system_roles.intersect?(...)` in `accounts.rb`'s system-role DELETE keep their current shape — they are deliberately preserved as smell-then-refactor fodder for a later branch.

## Questions

> Q1, Q2, … crossed off with decisions.

- [ ] **Q1 (token payload shape)**: full `Account#to_json` envelope (default) or lean `{id, username}`? Default: full envelope, ~1 KB token.
- [ ] **Q2 (route refactor scope)**: refactor all existing `courses.rb` + `accounts.rb` routes to drop `current_account_id` from request params/body, or do the gate at `app.rb` only? Default: full route refactor this week.
- [ ] **Q3 (test ordering)**: tests per layer or after all production code? Default: per layer for crypto/lib code; after for the route refactor.
- [ ] **Q4 (SendGrid live or stubbed in dev)**: live config in `secrets.yml` (user provisions), test stubs via WebMock? Default: yes.
- [ ] **Q5 (roll back the week-10 deviation that kept `id` in `Account#to_json` attributes?)**: with the token carrying identity, the response envelope no longer needs to leak `id`. Default: roll back unless the App still reads `current_account['id']` for non-API purposes (the App plan's Q4 audits this).

## Scope

**In scope — Payload 1 (token-based auth + registration verification)**:

- `Securable` lib (new, extracted from `SecureDB`)
- `AuthToken` lib (new)
- `VerifyRegistration` service (new)
- `POST /api/v1/auth/register` route (new)
- `AuthenticateAccount` returning `{account, auth_token}` envelope
- `HttpRequest#authenticated_account` + `app.rb` `@auth_account` plumbing
- `courses.rb` + `accounts.rb` controllers refactored from `current_account_id` params/body → `@auth_account` (Bearer-derived). Includes the system-role PUT/DELETE routes.
- `newkey:msg` rake task
- `MSG_KEY` + `SENDGRID_*` in `secrets-example.yml`
- Gemfile: add `http`, add `webmock` to `:test` group
- Updated specs
- `Account#to_json` rollback (remove `id` from `attributes`), per Q5

**In scope — Payload 2 (attendance check-in)**:

- Migration: `attendances` table (`id, account_id, event_id, course_id, checked_in_at`). Unique `(account_id, event_id)`. **No coord columns** — those land in a later branch as an additive `alter_table`.
- `Attendance` Sequel model (`belongs_to :account, :event, :course`, `whitelist_security` allows `:account_id, :event_id, :course_id`).
- `Event` model gains `live_now?` predicate and `live_now` class-level dataset filter. `Event#to_json` includes `my_attendance_id` when the caller has an attendance row for the event.
- `RecordAttendance` service (new) — inline role check (student-enrolled-in-course). Raise `NotAuthorizedError` / `UnknownEventError` as appropriate. Returns the new `Attendance` row. *Inline check is intentional and stays scattered for now per project rules.*
- `ListEligibleEvents` service (new) — caller's enrollments where role is `student`, joined to `Event.live_now`, minus events with existing attendance rows for the caller.
- Routes (under existing `courses.rb`):
  - `POST /api/v1/courses/[id]/attendances` — body `{event_id}`. 201 + new attendance JSON. 403 if non-student. 404 if event/course unknown. 409 on duplicate.
  - `GET /api/v1/courses/[id]/attendances` — caller's own attendances for this course.
  - `GET /api/v1/courses/[id]/attendances/[event_id]` — teaching-staff only (inline `role.intersect?(Role::TEACHING)`). All attendances for this event.
- Routes (new top-level `attendances.rb` controller, wired into `app.rb`'s `multi_route`):
  - `GET /api/v1/attendances/eligible` — cross-course list of events the caller can currently check into. Powers the App's home-page "eligible right now" block.
- Tests: `spec/integration/api_attendances_spec.rb` (HAPPY student check-in, BAD non-student → 403, BAD no token → 401, BAD duplicate → 409, list-own HAPPY, staff GET HAPPY + non-staff → 403, eligible-list HAPPY + filters non-live + filters already-attended). `spec/integration/service_record_attendance_spec.rb` (inline-check unit coverage).

**Out of scope** (deferred per project rules — do not creep in):

- Token scopes (resource:permission strings)
- Policy objects (including `AttendancePolicy`)
- Refactor of inline role checks (including the new one in `RecordAttendance`)
- Encrypted attendance coordinates (`longitude_secure`, `latitude_secure`) — additive migration in a later branch
- Geo half of attendance eligibility (haversine, ~55 m) — only the time half ships now
- Staff `PUT /attendances/[event_id]/[account_id]` (toggle) — later branch
- Token revocation list / refresh tokens
- Email rate limiting / abuse prevention

## Security Concerns Addressed This Week

1. **Email-based registration verification.** Two-step registration: collect `{email, username}`, send a SimpleBox-encrypted token by email, and only create the account when the user clicks the link and sets a password.
2. **Distributing trust via auth tokens.** The API issues an `auth_token` as a symbol of its trust in the just-authenticated user. The App carries the token on every subsequent API call. The API no longer trusts client-supplied `current_account_id`.
3. **Defense in depth via mixins.** `Securable` extraction turns cryptographic primitives into a reusable building block so `AuthToken` can use the same SimpleBox machinery without coupling to the database-encryption purpose.
4. **Encrypted, not just signed, tokens.** `SimpleBox` (XSalsa20-Poly1305 AEAD) provides both confidentiality and integrity. Expiration timestamp is part of the encrypted payload, not a separate query-string field.

## Tasks

> Check tasks off as soon as each one is finished — do not batch.

### Setup

- [ ] Branch `6-auth-token` created off `main`
- [ ] `CLAUDE.local.md` updated to point at this plan
- [ ] Plan-first commit (`docs: plan 6-auth-token`)

### Gemfile

- [ ] Add `gem 'http', '~>5.1'`
- [ ] Add `gem 'webmock'` to `:test` group
- [ ] `bundle install`

### Library — crypto

- [ ] `app/lib/securable.rb`: new module with `generate_key`, `setup(base_key)`, `key`, `base_encrypt(plaintext)`, `base_decrypt(ciphertext)`
- [ ] `app/lib/secure_db.rb`: refactor to `extend Securable`. Keep `hash` method + `@hash_key` storage. `setup(db_key, hash_key)` calls `super(db_key)` then stores `@hash_key`.
- [ ] `app/lib/auth_token.rb`: new lib `extend Securable`. `ONE_HOUR..ONE_YEAR` constants. `create(payload, expiration)`, `new(token).payload`, `expired?`, `fresh?`, `to_s`. Errors: `ExpiredTokenError`, `InvalidTokenError`.

### Library — registration

- [ ] `app/services/verify_registration.rb`: SendGrid HTTP call. Validates username availability with `Account.first(username:).nil?` and email availability with `Account.first(email_hash: SecureDB.hash(plaintext)).nil?`. Sends an HTML email. Errors: `InvalidRegistration`, `EmailProviderError`.

### Authentication

- [ ] `app/services/authenticate_account.rb`: return `{ type: 'authenticated_account', attributes: { account: <Account#to_json envelope>, auth_token: AuthToken.create(account, AuthToken::ONE_WEEK).to_s } }`. Keep `UnauthorizedError`.

### Bearer plumbing

- [ ] `app/controllers/http_request.rb`: add `authenticated_account` — reads `Authorization` header, splits on whitespace, `Bearer`-matches, `AuthToken.new(token).payload`, returns `payload['attributes']`.
- [ ] `app/controllers/app.rb`: after the `secure?` check, parse the Bearer header → set `@auth_account`. Rescue `AuthToken::InvalidTokenError` → 403 `Invalid auth token`.

### Routes — refactor

- [ ] `app/controllers/auth.rb`:
  - Add `routing.on 'register'` block with `routing.post` → calls `VerifyRegistration`. 202 on success; 400 on `InvalidRegistration`; 500 on `EmailProviderError`.
  - Keep `routing.is 'authenticate'`; service now returns envelope, route just `to_json`s it.
- [ ] `app/controllers/courses.rb`: every route drops `current_account_id` reads from query params / body. Switch to `@auth_account['attributes']['id']`. Return 401 if `@auth_account` is nil.
- [ ] `app/controllers/accounts.rb`: same refactor. `POST /accounts` stays open. The system-role PUT/DELETE routes and `GET /accounts/:username` switch to `@auth_account['attributes']['id']`. **Inline role checks (`system_roles.intersect?(...)`, etc.) are unchanged.**

### Account model — `to_json` rollback (per Q5)

- [ ] If Q5 = roll back: drop `id` from `Account#to_json`'s `attributes` block. The token still carries `id` in its encrypted payload; the API just stops exposing it in plaintext responses. Update `spec/integration/api_auth_spec.rb` if it asserts on `id`.

### Config

- [ ] `config/environments.rb`: add `AuthToken.setup(ENV.delete('MSG_KEY'))` after the existing `SecureDB.setup` line.
- [ ] `config/secrets-example.yml`: add `MSG_KEY`, `SENDGRID_API_KEY`, `SENDGRID_FROM_EMAIL`, `SENDGRID_API_URL` for `development`, `test`, `production` blocks.

### Rakefile

- [ ] Add `newkey:msg` task that prints `MSG_KEY: <generated>` using the same RbNaCl random-bytes pattern as `newkey:db` / `newkey:hash`.

### Tests

- [ ] Update `spec/integration/api_auth_spec.rb` to assert the new envelope (`attributes.account` + `attributes.auth_token`).
- [ ] Update `spec/integration/api_courses_spec.rb` (and any sibling) to send `Authorization: Bearer <token>` on every authenticated call; assert 403 / 401 without it.
- [ ] Update `spec/integration/api_accounts_spec.rb` similarly. `POST /accounts` test stays anonymous; system-role tests use Bearer.
- [ ] Add `spec/lib/auth_token_spec.rb` (create / detokenize / `expired?` / `InvalidTokenError`).
- [ ] Add `spec/integration/service_authenticate_account_spec.rb`.
- [ ] (Optional, per Q3) Add `spec/integration/service_verify_registration_spec.rb` with WebMock for SendGrid.

### Attendance (Payload 2)

- [ ] Migration `db/migrations/00X_attendances_create.rb` — additive, no coord columns.
- [ ] `app/models/attendance.rb` (new) — associations + whitelist + timestamps.
- [ ] `app/models/event.rb` — add `live_now?` predicate, `live_now` dataset filter, and `my_attendance_id` field in `to_json` when caller-scoped.
- [ ] `app/services/record_attendance.rb` (new) — inline role check; raises `NotAuthorizedError`, `UnknownEventError`.
- [ ] `app/services/list_eligible_events.rb` (new) — eligible-now query.
- [ ] `app/controllers/courses.rb` — add `routing.on 'attendances'` block under `routing.on String do |course_id|` with POST + GET + staff `routing.get String do |event_id|`.
- [ ] `app/controllers/attendances.rb` (new) — top-level controller; `routing.is 'eligible'` returns the cross-course eligible list.
- [ ] `app/controllers/app.rb` — register the new `attendances` route in `multi_route`.
- [ ] `spec/integration/api_attendances_spec.rb` — full coverage matrix above.
- [ ] `spec/integration/service_record_attendance_spec.rb` — service-level coverage of the inline role check.

### Verify

- [ ] `bundle exec rake spec` green
- [ ] `bundle exec rubocop .` green
- [ ] `bundle exec bundle-audit check --update` green
- [ ] Code review
- [ ] Retrospective migration audit (diff-level, full-tree, shared-file content diff). Payload 2 has no reference counterpart — audit it on its own (no Credence shared-file diff applies).
- [ ] Squash / split into 2 payload commits
- [ ] Merge PR to `main` — deferred to user, done manually later in the week after class
- [ ] Skill self-reflection

## Commit strategy

- **Required commit count**: 2 payload commits. Payload 1 mirrors the reference branch's shape (token-based auth + email verification + route refactor). Payload 2 is a Tyto domain extension: basic attendance check-in.
- **Final branch shape**:
  ```
  docs: plan 6-auth-token
  Sends out verification email and requires token-based authorization   ← payload 1
  Adds attendance check-in and eligibility listing                       ← payload 2
  ```
- **Payload 1 subject**: `Sends out verification email and requires token-based authorization`.
- **Payload 2 subject**: `Adds attendance check-in and eligibility listing`. Body notes the inline role check in `RecordAttendance` as a deliberate smell preserved for a later policy-extraction branch, and that encrypted coords + geo-validation arrive in a later branch alongside the geo half of attendance eligibility.

## Infrastructure setup (user-operated)

These are reference instructions for the operator — not tasks for the AI. The AI provides commands; the operator runs them.

1. **Provision a SendGrid sandbox account** (free tier):
   - Visit `https://sendgrid.com` and "Start for Free".
   - Verify the operator email (consider an alias for class purposes).
   - Create a Single Sender Profile (this is the verified `from` address).
   - Provision an API key (Settings → API Keys → "Full Access" or "Mail Send" only).
2. **Set local secrets** in `config/secrets.yml` for `development` and `test`:
   ```yaml
   MSG_KEY: <run `rake newkey:msg`>
   SENDGRID_API_KEY: <pasted from SendGrid console>
   SENDGRID_FROM_EMAIL: <the verified Single Sender address>
   SENDGRID_API_URL: https://api.sendgrid.com/v3/mail/send
   ```
3. **Production env vars** on the PaaS:
   ```bash
   heroku config:set -a <api-app-name> MSG_KEY=<paste>
   heroku config:set -a <api-app-name> SENDGRID_API_KEY=<paste>
   heroku config:set -a <api-app-name> SENDGRID_FROM_EMAIL=<verified address>
   heroku config:set -a <api-app-name> SENDGRID_API_URL=https://api.sendgrid.com/v3/mail/send
   ```
4. **Verify production**: trigger a registration through the deployed App after both repos' branches are merged. Confirm the verification email lands in the test inbox.

## Completed

(to be filled in during implementation)

## Post-Implementation Notes (for reviewer)

(to be filled in before handing off for review)

---

Last updated: 2026-05-12
