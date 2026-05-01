# 4-authenticate — Auth route, multi-route controllers, HttpRequest helper

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update before and after task and subtask implementations.

## Branch

`4-authenticate`

## Goal

Add a credential-verification route (`POST /api/v1/auth/authenticate`) and reshape the API around two controller-level abstractions:

1. **`multi_route` plugin** — split `app/controllers/app.rb` into `accounts.rb`, `courses.rb`, and `auth.rb`, mounted under `/api/v1` via named route blocks.
2. **`HttpRequest` helper** — encapsulate per-request scheme enforcement (`secure?`) and JSON body parsing (`body_data`), and use it from every controller.

Adapted from the reference API branch.

## Strategy: Vertical Slice

1. Land the `secure?` enforcement and `HttpRequest` helper first (request-layer plumbing).
2. Add `multi_route` + extract `accounts.rb` and `courses.rb` (with nested events/locations/enrollments) from `app.rb`; thin `app.rb` to dispatch only.
3. Add `auth.rb` controller + `AuthenticateAccount` service.
4. Normalize all model `to_json` envelopes to `{type, attributes, [include]}` (no `data:` wrapper, `include:` not `included:`).
5. Embed enrollments inside `Account#to_json` so the app can render "my courses" in one round-trip.
6. Update integration specs to consume the new envelope; add `api_auth_spec.rb`.
7. Gemfile reorg + Rakefile additions.

## Current State

- [x] Plan created
- [x] Branch created off `main`
- [x] Plan committed as `docs: plan 4-authenticate`
- [x] `CLAUDE.local.md` updated to point at this plan
- [x] All tasks below
- [x] Code review
- [x] Retrospective migration audit
- [x] Squash to required commit count
- [ ] Merge PR to `main` — deferred to user, done manually later in the week after class

## Key Findings

### Starting point (tip of `main`)

- `app/controllers/app.rb` is one monolith with all routes (accounts, courses with nested events/locations/enrollments). 237 lines.
- Models have **inconsistent** `to_json` envelopes:
  - `Account`: `{type, id, username, email}` (flat)
  - `Course`: `{data: {type, attributes}}` (nested with `data:` wrapper)
  - `Event`, `Location`: `{data: {type, attributes}, included: {...}}` (nested with `data:` and `included:`)
  - `Enrollment`: `{id, account_id, course_id, role}` (flat, no envelope)
- Specs expect the inconsistent shapes (e.g., `api_accounts_spec.rb` reads `result['id']` flat).
- Gemfile has an orphan `# Performance` group with just `rubocop-performance` outside any group.
- `config/secrets.yml` does not yet carry `SECURE_SCHEME`.
- No `app/controllers/auth.rb`, no `app/services/authenticate_account.rb`, no `api_auth_spec.rb`.

### Threat model delta vs starting point

| Risk | Addressed here |
| --- | --- |
| Plaintext credentials over plain HTTP in non-dev | `HttpRequest#secure?` halts 403 unless `routing.scheme` matches `SECURE_SCHEME` for the env |
| Brittle/duplicated credential checks scattered across routes | Centralized `AuthenticateAccount` service raising `UnauthorizedError`; auth route is the only credential-verification surface |
| Mass-assignment / illegal attributes through credential POST | `AuthenticateAccount` only reads `username` + `password`; rescues all errors uniformly and reports generic 403 (no info leak) |
| Inconsistent JSON envelopes across models | All models normalized to `{type, attributes, [include]}` |
| Body-parsing repeated ad hoc per route | `HttpRequest#body_data` centralizes `JSON.parse(..., symbolize_names: true)` |

### Domain scope (this branch only)

No new entities. Reshapes existing models' JSON output and adds an auth surface. Account model already has `password?`; we just call it.

## Decisions

- **D1** — Drop the orphan `# Performance` Gemfile group; consolidate rubocop-* gems into `:development`.
- **D2** — Keep `db:delete` Rake task with explicit cascade across Event / Location / Enrollment / Account / Course (do not collapse to `Account.dataset.destroy`); FK cascade rules are not uniformly set.
- **D3** — **Keep `id` in `Account#to_json` attributes** (intentional deviation from the reference API). The web app needs `session[:current_account]['id']` to send `current_account_id` to authenticated POST routes, matching the trust pattern established in the previous branch.
- **D4** — Keep `id` in `attributes` for Course / Event / Location / Enrollment.
- **D5** — Embed enrollments inside `Account#to_json` (`include: { enrollments: [...] }`) as compact `{course_id, course_name, role}` hashes. Saves N+1 fetches when the app shows the user's courses.
- **D6** — Collapse the multi-route refactor and the HttpRequest extraction into a **single payload commit** (the reference API ships them as two; we ship as one).

## Questions

> All questions resolved during plan phase. None outstanding.

## Scope

**In scope:**

- `multi_route` plugin in `app.rb`; extract `accounts.rb` and `courses.rb` controllers (events/locations/enrollments stay nested under courses, mirroring the reference API's documents-under-projects pattern).
- `auth.rb` controller + `AuthenticateAccount` service + `UnauthorizedError`.
- `HttpRequest` helper class with `secure?` and `body_data`; use from all controllers.
- `SECURE_SCHEME` config across dev/test/prod environments.
- JSON envelope normalization across `Account`, `Course`, `Event`, `Location`, `Enrollment`.
- Embed enrollments in `Account#to_json`.
- Gemfile reorganization.
- Rakefile: add `run:dev` task.
- Specs: rewrite all integration specs to expect new envelope; add `api_auth_spec.rb`.

**Out of scope** (deferred per project rules):

- Token issuance / encrypted tokens
- Email verification
- Production-database / TLS deployment infrastructure
- Authorization policies (role-based gating of routes)
- Token scopes / geo-validation

## Tasks

> Check tasks off as soon as each one is finished — do not batch.

### Setup

- [x] 1. Create branch `4-authenticate` off `main`.
- [x] 2. Commit plan file as `docs: plan 4-authenticate`.
- [x] 3. Update `CLAUDE.local.md` to point at `@.claude/plans/PLAN.4-authenticate.md`.

### Gemfile

- [x] 4. Move `rubocop`, `rubocop-minitest`, `rubocop-performance`, `rubocop-rake`, `rubocop-sequel`, `bundler-audit`, `rerun` into a single `group :development do ... end` block. Drop the orphan `# Performance` comment line.
- [x] 5. Move `rack-test` into `group :development, :test do ... end` alongside `sequel-seed` and `sqlite3`.
- [x] 6. Keep `pry` outside groups.
- [x] 7. `bundle install` and verify `Gemfile.lock` is regenerated.

### Config / secrets

- [x] 8. Add `SECURE_SCHEME: HTTP` to `config/secrets-example.yml` under `development` and `test`; `SECURE_SCHEME: HTTPS` under `production`.
- [x] 9. Mirror the same change into `config/secrets.yml` (gitignored — manual edit).

### Models — JSON envelope normalization

For each model: align `to_json` to `{type:, attributes: {...}, [include: {...}]}` (no `data:` wrapper, `include:` not `included:`).

- [x] 10. `app/models/account.rb`: `{type: 'account', attributes: {id, username, email}, include: {enrollments: [...]}}`. **Keep `id`** (D3). Embed enrollments as a compact array of `{course_id, course_name, role}` hashes (D5); each enrollment dereferences `enrollment.course.name` and `enrollment.role.name`.
- [x] 11. `app/models/course.rb`: `{type: 'course', attributes: {id, name, description}}` — drop the `data:` wrapper.
- [x] 12. `app/models/event.rb`: `{type: 'event', attributes: {id, name, start_at, end_at}, include: {course, location}}` — drop `data:`, rename `included:` → `include:`.
- [x] 13. `app/models/location.rb`: `{type: 'location', attributes: {id, name, longitude, latitude}, include: {course}}` — drop `data:`, rename `included:` → `include:`.
- [x] 14. `app/models/enrollment.rb`: `{type: 'enrollment', attributes: {id, account_id, course_id, role}}` — wrap in the standard envelope.

### Controllers + services

- [x] 15. Add `app/controllers/http_request.rb` with `Tyto::HttpRequest`:
  - `initialize(roda_routing)` stores `@routing`
  - `secure?` raises if `Api.config.SECURE_SCHEME` unset; otherwise compares `@routing.scheme.casecmp(...)` to zero
  - `body_data` returns `JSON.parse(@routing.body.read, symbolize_names: true)`
- [x] 16. Refactor `app/controllers/app.rb`:
  - Add `plugin :multi_route`
  - Add the early-return `HttpRequest.new(routing).secure? || routing.halt(403, { message: 'TLS/SSL Required' }.to_json)` after `response['Content-Type'] = 'application/json'`
  - Replace inline route bodies with `routing.on 'api' do; routing.on 'v1' do; @api_root = 'api/v1'; routing.multi_route; end; end`
  - Drop the `rubocop:disable Metrics/ClassLength` comment if no longer needed.
- [x] 17. Add `app/controllers/accounts.rb` with `route('accounts')`:
  - `routing.on String do |username|` → `GET` returns `Account.first(username:).to_json` or 404
  - `routing.post` uses `HttpRequest.new(routing).body_data`, creates `Account.new`, saves, returns 201 with `Location` and `{message, data}` body
  - Rescue `Sequel::MassAssignmentRestriction` → 400; `StandardError` → 500
- [x] 18. Add `app/controllers/courses.rb` with `route('courses')`:
  - Move all current course / nested events / nested locations / nested enrollments routes from `app.rb` into this file unchanged in semantics
  - Replace every `JSON.parse(routing.body.read)` callsite with `HttpRequest.new(routing).body_data` (returns symbol keys; rewrite `body['current_account_id']` reads as `body[:current_account_id]` and adapt `slice` calls accordingly)
- [x] 19. Add `app/controllers/auth.rb` with `route('auth')`:
  - `routing.is 'authenticate' do; routing.post do ...` calls `AuthenticateAccount.call(HttpRequest.new(routing).body_data)`, returns `auth_account.to_json` on success
  - Rescue `UnauthorizedError` → halt 403 with `{message: 'Invalid credentials'}.to_json`; `puts [e.class, e.message].join ': '` (so the spec's `assert_output(/invalid/i, '')` passes)
- [x] 20. Add `app/services/authenticate_account.rb`:
  - `UnauthorizedError < StandardError` with custom `message` method that includes `@credentials[:username]`
  - `AuthenticateAccount.call(credentials)` — finds account by username, calls `account.password?(credentials[:password])`, returns the account or raises `UnauthorizedError` with the credentials hash

### Rakefile

- [x] 21. Add `namespace :run do; desc 'Run API in development mode'; task :dev do; sh 'puma -p 3000'; end; end`.
- [x] 22. Keep `db:delete` task as-is with explicit cascade (D2).

### Tests

- [x] 23. Update `spec/integration/api_accounts_spec.rb`:
  - Add `@req_header = { 'CONTENT_TYPE' => 'application/json' }` to the outer `before` block
  - Rewrite GET assertion: `attributes = JSON.parse(last_response.body)['attributes']` then assert `attributes['id']`, `attributes['username']`, `attributes['email']`; assert `attributes['salt']` / `password*` / `email_secure` / `email_hash` are nil
  - Add new GET test case: account with enrollments → `JSON.parse(...)['include']['enrollments']` is an array of `{course_id, course_name, role}` hashes; account with no enrollments → empty array
  - Rewrite POST assertion: `created = JSON.parse(last_response.body)['data']['attributes']`
- [x] 24. Update `spec/integration/api_courses_spec.rb` to read `result['attributes']['id']` / `result['attributes']['name']`; list endpoint expects an array of `{type:'course', attributes:{...}}` items.
- [x] 25. Update `spec/integration/api_events_spec.rb` similarly.
- [x] 26. Update `spec/integration/api_locations_spec.rb` similarly.
- [x] 27. Update `spec/integration/api_enrollments_spec.rb` to expect the new envelope.
- [x] 28. Update `spec/integration/service_create_course_for_owner_spec.rb` if it asserts on `to_json` shape.
- [x] 29. Add `spec/integration/api_auth_spec.rb`:
  - HAPPY: post valid credentials → 200, returns `{type:'account', attributes: {id, username, email}, include: {enrollments: [...]}}`
  - BAD: post wrong password → 403, response includes `message`, `attributes` is nil, captures stderr matching `/invalid/i`
- [x] 30. Verify `spec/integration/api_spec.rb` (root route) still passes — should be unaffected.

### Verify

- [x] 31. `bundle exec rake spec` — all green.
- [x] 32. `bundle exec rubocop .` — clean (consider whether to lift `app/controllers/*.rb` from the BlockLength exclusion now that controllers are smaller).
- [x] 33. `bundle exec bundle-audit check --update` — clean.
- [x] 34. Manual smoke test: boot `rake run:dev`, `curl -X POST http://localhost:3000/api/v1/auth/authenticate -d '{"username":"...","password":"..."}'` against a seeded account; expect 200 with the new envelope including `id` and embedded enrollments. Repeat with bad password → 403.
- [x] 35. Code review.
- [x] 36. Retrospective migration audit:
  - `git -C <ref-api> show --name-status <ref-payload-1>`
  - `git -C <ref-api> show --name-status <ref-payload-2>`
  - `git show --name-status <tyto-payload-sha>` — reconcile every entry. Substitution table: `accounts.rb`/`auth.rb` 1:1; `projects.rb` ↔ `courses.rb`; specs 1:1 with `accounts/courses/events/locations/enrollments`.
  - Full-tree diff vs the reference API's branch tip — note the reference's domain-only files (e.g., `projects.rb`) and Tyto-only files (`enrollment.rb`, `event.rb`, `location.rb`, `role.rb`, etc.).
  - Content diff on shared filenames — every difference must be a documented domain swap, version pin, or noted preference.
  - Note: the reference's payload-2 deletes a stale `spec/projects_spec.rb`; no Tyto equivalent — skip with reason.
- [x] 37. Squash to 1 payload commit (D6 collapse).
- [x] 38. **Author handoff doc** for `/ppt-update`: write `baby_tyto/design-notes/auth-trust-model-week-10.md` covering the intentional API trust gap (client-supplied `current_account_id`), CSRF deferral, geolocation hard-fail, and the Account `id` deviation. This file is shared with the App branch's same task.
- [ ] 39. Merge PR to `main` — deferred to user, done manually later in the week after class.
- [x] 40. **Skill self-reflection**: re-read `/week-plan` SKILL.md and propose refinements if this week surfaced any gaps.

## Commit strategy

- **Required commit count**: **1 payload commit** (collapsed from the reference's 2 payload commits per D6).
- **Subject (proposed)**: `Authenticates credentials, splits routes, and extracts HttpRequest helper`
  - Body: bullet list covering — auth route + service, multi_route extraction (accounts.rb, courses.rb), HttpRequest helper, JSON envelope normalization, Account `id` retention + embedded enrollments. Note the collapse override.
- **Plan commit** (`docs: plan 4-authenticate`) does not count toward the payload total.

## Completed

Shipped as a single payload commit `Authenticates credentials, splits routes, and extracts HttpRequest helper` (D6 collapse honored). All in-scope items landed: auth route + service, multi_route extraction (`accounts.rb`/`courses.rb`/`auth.rb`), `HttpRequest` helper, `SECURE_SCHEME` config, JSON envelope normalization, Account `id` retention + embedded enrollments (D3 + D5), Enrollment envelope embeds `{account: {username}}`, Gemfile reorg, `rake run:dev`. Specs all pass; rubocop clean; bundle-audit clean. Handoff doc for `/ppt-update` lives at `baby_tyto/design-notes/auth-trust-model-week-10.md` (shared with the App branch).

## Post-Implementation Notes (for reviewer)

- D6 collapse honored: 1 payload commit (Credence ships 2). Rationale recorded in commit body.
- D3: `Account#to_json` keeps `id` in `attributes` — required by App's session-based trust pattern; this is the intentional weakness the next branch (`6-auth-token`) closes.
- D5: enrollments embedded in `Account#to_json` to avoid N+1 fetches in the App's `role_for_course` UI gate.
- Inline per-route `current_account_id` gates (instead of policy objects) are deliberate scaffolding — the `7-policies` branch uses this file as the demo for why Policy objects exist.
- Cosmetic preferences not mirrored: none material this week.

## Carryover for future branches

- **Account first/last names**: when registration ships in `6-auth-token`, grow the `accounts` table with `first_name` / `last_name` columns and update `Account#to_json`, the seed YAML, and the enrollment envelope's `include.account` block to surface them. PII discussion (encrypt? hash? plaintext?) parallels the existing `email_secure` / `email_hash` design — worth its own design note in `baby_tyto/design-notes/`. Until then, the App displays `account.username` (added to the Enrollment envelope as a follow-up to this branch) in places like `_enrollment_row.slim` as a pragmatic stand-in for a full name.

---

Last updated: 2026-04-28
