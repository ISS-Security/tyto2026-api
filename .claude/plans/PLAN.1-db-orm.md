# 1-db-orm — Relational Database with Sequel ORM

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update this plan before and after task and subtask implementations.

## Branch

`1-db-orm`

## Goal

Replace the ad-hoc file store from the previous branch with a real relational database (SQLite for dev/test, Postgres-ready for production later) backing the Tyto domain. Introduce the `Course → Event, Location` skeleton so the rest of the backend has a real schema to grow into.

This is a foundation branch: no user-facing behavior changes beyond a richer set of routes, but the features scheduled for later weeks depend on having a persistent store, an ORM boundary, and secrets/config hygiene in place.

## Strategy: Vertical Slice

Deliver a complete, testable slice end-to-end:

1. **Dependency + config layer** — Sequel, SQLite, Figaro, `ENV.delete` for secrets, autoloader
2. **Schema layer** — migrations for `courses`, `locations`, `events`
3. **Model layer** — `Sequel::Model` classes with associations and JSON serialization
4. **Controller layer** — nested resource routes under `/api/v1/courses/[id]`
5. **Ops layer** — `Rakefile` with `db:*`, `spec`, `style`, `audit`, `release_check`
6. **Verify** — `rake spec`, `rubocop`, `bundle audit` all green; secrets not exposed in test

## Current State

- [x] Plan created
- [x] Branch created off `main`
- [x] Dependencies added and locked (`bundle install` clean)
- [x] Figaro + Sequel connection wired in `config/environments.rb`
- [x] `DATABASE_URL` deleted from `ENV` after read
- [x] `config/secrets.yml` gitignored; `config/secrets-example.yml` committed
- [x] `require_app.rb` + `config.ru` autoloading in place
- [x] Migrations 001–003 applied to dev and test DBs
- [x] Models (`Course`, `Location`, `Event`) with associations and JSON
- [x] Nested controller routes for events and locations
- [x] Seeds for all three entities
- [x] Spec suite (root, env, courses, locations, events) — 14 runs / 37 assertions / 0 failures
- [x] Rubocop clean (including `rubocop-performance`, `-rake`, `-sequel` plugins)
- [x] `bundle audit check --update` clean
- [ ] Code review
- [ ] Merge to `main`

## Key Findings

### Starting point (`main` after the previous branch)

- File-based `Course` store under `db/local/*.txt`, keyed by a base64-encoded SHA256 of `Time.now.to_f` — collision-prone and impossible to scale beyond a single host.
- Single flat `spec/api_spec.rb` with hand-rolled DB wipes via `Dir.glob`.
- `config.ru` required the controller directly; no autoloader.
- `rbnacl` pinned at `~>7.0`, `puma` at `~>7.0`, Ruby `4.0.1`. No `rake`, no `sequel`, no `figaro`.
- `.gitignore` already excludes `_*` and `db/local/*` but has no entry for `config/secrets.yml` — we need one before anything touches secrets.

### What the database migration actually needs to address

From a threat-model standpoint, this branch is where the following risks from the file-store era get closed or explicitly scoped out:

| Risk in the previous branch | Addressed here | Deferred |
| --- | --- | --- |
| IDs collide within a 1-second window | Sequel autoincrement PKs | — |
| Data store only on one host | Real DB (Postgres-ready later) | Production DB wiring later |
| Raw `File.read`/`File.write` — no query layer | Sequel parameterized queries | — |
| `YAML.safe_load` is fine today but someone could regress to `YAML.load` | Keep `YAML.safe_load_file` everywhere; RuboCop `Security/YAMLLoad` enforced | — |
| Dependency vulnerabilities invisible | `bundler-audit` + `rake audit` + `rake release_check` | — |
| Performance smells in code invisible | `rubocop-performance`, `-sequel` linters | — |
| Secrets could land in `ENV` and leak to child processes / gems | `ENV.delete('DATABASE_URL')` in `config/environments.rb`, verified by `spec/env_spec.rb` | — |
| Encryption of PII at rest | — | Deferred per project rules |
| Authentication / authorization / ownership | — | Deferred per project rules |

### Domain scope (this branch only)

- `Course` — `name`, `description`. No `owner_id` yet; ownership is deferred.
- `Location` — `course_id`, `name`, `longitude`, `latitude`. Matches the full Tyto schema exactly; no `address` column.
- `Event` — `course_id`, `location_id`, `name`, `start_at`, `end_at`. `location_id` is nullable (not every event needs a physical location), `course_id` is `null: false`.

## Questions

> Questions must be numbered (Q1, Q2, ...) and crossed off when resolved. Note the decision made.

- [x] ~~Q1. What SQLite gem version should we pin?~~ — **`~>2.0`.** Ruby 4.0.1 / modern bundler needs the `2.x` line. Note it in the post-review notes.
- [x] ~~Q2. Do we introduce `Event` and `Location` now, or just `Course`?~~ — **All three.** The whole point of this branch is to lay the schema for later features, and events/locations are the minimum viable set. Doing it in one branch avoids re-migrating twice in two weeks.
- [x] ~~Q3. Should `Location` carry an `address` column?~~ — **No.** Full Tyto's `locations` table has only `name`, `latitude`, `longitude`. Dropped `address` to stay faithful to the source schema; `2-db-hardening` will encrypt location coordinates instead, which also foreshadows the attendance-coordinate encryption in `8-auth-scope`.
- [x] ~~Q4. Should `Event.location_id` be required?~~ — **No.** Allow `null` so the test fixtures can create events without a location, and so the later "async event" story stays open. The FK constraint is there either way.
- [x] ~~Q5. Do we introduce `owner_id` on `Course` now to avoid a backfill later?~~ — **No.** There's no `accounts` table to point at — it will be added in later weeks.
- [x] ~~Q6. `hirb` is kind of old — do we still want it for `rake console`?~~ — **No.** Let's update it `table_print`.
- [x] ~~Q7. YAML-load `Time` for `event_seeds.yml`?~~ — **Use `YAML.safe_load_file(..., permitted_classes: [Time])`.** Explicit allowlist is the safe-by-default pattern; never fall back to `YAML.load`.
- [x] ~~Q8. What JSON envelope shape should we use?~~ — **`{ data: { type, attributes }, included }`.** Matches what the future `tyto2026-app` will expect and gives us a clean "resource / relationships" story without pulling in a heavy serializer gem.
- [x] ~~Q9. Should `rake spec` depend on `rake db:migrate` for the test DB?~~ — **No.** Keep them separate so a broken migration fails loudly on its own and doesn't get swallowed by the spec task. Document the `RACK_ENV=test rake db:migrate` one-time setup in the README.
- [x] ~~Q10. Can we commit a `Gemfile.lock` that upgrades transitive gems?~~ — **Yes.** Everything is green and audit is clean. The lock update is a natural consequence of adding new gems.

## Scope

**In scope**:

- Sequel + SQLite3 dev/test infrastructure
- Figaro-based secrets management with gitignored `secrets.yml`
- Migrations for `courses`, `locations`, `events` with FKs and sensible unique constraints
- `Sequel::Model` classes with `one_to_many` / `many_to_one` and `association_dependencies` for cascading destroy
- Rewriting `app/controllers/app.rb` to expose:
  - `GET/POST /api/v1/courses`
  - `GET /api/v1/courses/[course_id]`
  - `GET/POST /api/v1/courses/[course_id]/events`
  - `GET /api/v1/courses/[course_id]/events/[event_id]`
  - `GET/POST /api/v1/courses/[course_id]/locations`
  - `GET /api/v1/courses/[course_id]/locations/[location_id]`
- `Rakefile` with `spec`, `style`, `audit`, `release_check`, `console`, and `db:{load,load_models,migrate,delete,drop}`
- Spec suite following the HAPPY / SAD (/ BAD when applicable) convention
- An explicit test that secret config vars do not leak through `Api.config`
- README updated for the new workflow

**Out of scope** (deferred per project rules — do not creep in):

- Encryption at rest
- Accounts, password hashing, email HMAC, `Course#owner_id`
- Authentication routes and services
- Production deployment wiring
- Auth tokens, registration, verification emails
- Enrollment, attendance, policy/authorization objects
- Geo validation and attendance coordinate encryption

## Security Concerns Addressed This Week

These are the things a reviewer should explicitly confirm are in place before this branch merges.

1. **Dependency vulnerability auditing is wired in.**
   - `bundler-audit` is a dev dependency.
   - `rake audit` calls `bundle audit check --update`.
   - `rake release_check` depends on `audit`, so the branch can't "ship" with a known-vulnerable gem.
2. **Static analysis catches perf/ORM/rake footguns.**
   - `rubocop-performance`, `rubocop-rake`, `rubocop-sequel` plugins are loaded.
   - Example coverage: `Sequel/SaveChanges` catches accidental `.save` in specs and controllers; `Rake/Desc` forces every task to document itself.
3. **Deployment environment is explicit.**
   - `ENV['RACK_ENV']` drives everything via Roda's `:environments` plugin and Figaro's `environment:` parameter.
   - `spec/spec_helper.rb` sets `RACK_ENV=test` as the very first line, before any app code loads.
4. **Secrets are not committed.**
   - `config/secrets.yml` is in `.gitignore`.
   - `config/secrets-example.yml` is the template; it documents shape, not values.
   - Production `DATABASE_URL` is intentionally unset in the example and is expected to come from the host's real env.
5. **Secrets are not leaked to child processes or dependent gems.**
   - `config/environments.rb` reads `DATABASE_URL` via `ENV.delete('DATABASE_URL')`, so once Sequel has the connection string, nothing downstream (gems, `sh` subprocesses, `rake` invocations) can see it in `ENV`.
   - `spec/env_spec.rb` asserts `Tyto::Api.config.DATABASE_URL` is `nil` — a regression test for the "someone accidentally switches to `ENV[...]` without `.delete`" mistake.
6. **ORM boundary prevents SQL injection by default.**
   - All queries go through `Sequel::Model` / `DB` — parameterized. There is zero string-concatenated SQL in this branch.
7. **Safe YAML.**
   - `spec/spec_helper.rb` uses `YAML.safe_load_file`. Where `Time` scalars are legitimately needed (`event_seeds.yml`), they are explicitly allowlisted via `permitted_classes: [Time]`.
   - RuboCop `Security/YAMLLoad` stays enabled outside `spec/**/*`.
8. **Dev DB artifacts stay out of git.**
   - `db/local/*.db` is already gitignored.
9. **Test/dev/prod separation at the schema level.**
   - Separate SQLite files per environment.
   - `rake db:drop` refuses to run in production.

## Tasks

> Check tasks off as soon as each one (or each grouped set) is finished — do not batch multiple completions before updating the plan.
>
> Test-first is applied at the suite level here, not per-task: the `courses_spec` / `locations_spec` / `events_spec` files were written alongside the models/controllers from the same blueprint. For a scaffolding branch this is the pragmatic call.

### Setup

- [x] 1. Create branch `1-db-orm` off `main`
- [x] 2. Update `Gemfile`:
  - add `figaro`, `rake`, `sequel`, `hirb`
  - add `sqlite3 ~>2.0` to `:development, :test` group
  - move `minitest`, `minitest-rg`, `rack-test` under `:test` group
  - add `rubocop-performance`, `rubocop-rake`, `rubocop-sequel`
  - bump `rbnacl` to `~>7.1`
- [x] 3. Update `.rubocop.yml`:
  - load new plugins
  - exclude `app/controllers/*.rb`, `spec/**/*`, `Rakefile` from `Metrics/BlockLength`
  - exclude `Rakefile`, `db/migrations/*.rb` from `Style/HashSyntax`, `Style/SymbolArray`
- [x] 4. `.gitignore`: add `.bundle`, `.irb_history`, `config/secrets.yml`
- [x] 5. Rewrite `README.md` with the new routes, `rake db:migrate`, `rake spec` workflow

### Config + autoload

- [x] 6. `config/environments.rb` — Figaro + Sequel `DB`, `ENV.delete('DATABASE_URL')`, `configure :development, :production { plugin :common_logger }`, `configure :development, :test { require 'pry' }`
- [x] 7. `config/secrets-example.yml` with dev/test SQLite URLs and a placeholder production entry
- [x] 8. Local `config/secrets.yml` (gitignored) for development
- [x] 9. `require_app.rb` autoloader
- [x] 10. `config.ru` → `require './require_app'; require_app; run Tyto::Api.freeze.app`

### Schema + seeds

- [x] 11. Migration `001_courses_create.rb` — `name` unique/not null, `description`, timestamps
- [x] 12. Migration `002_locations_create.rb` — FK `course_id`, `name` not null, `Float longitude/latitude`, timestamps, unique `(course_id, name)`
- [x] 13. Migration `003_events_create.rb` — FK `course_id` not null, FK `location_id` nullable, `name` not null, `start_at/end_at`, timestamps, unique `(course_id, name, start_at)`
- [x] 14. `db/seeds/course_seeds.yml` (cleaned up from the previous branch)
- [x] 15. `db/seeds/location_seeds.yml`
- [x] 16. `db/seeds/event_seeds.yml` with real `Time` scalars

### Models

- [x] 17. `app/models/course.rb` — `one_to_many :events, :locations`, `association_dependencies`, `plugin :timestamps`, JSON envelope
- [x] 18. `app/models/location.rb` — `many_to_one :course`, `one_to_many :events`, JSON envelope (includes `course`)
- [x] 19. `app/models/event.rb` — `many_to_one :course, :location`, JSON envelope (includes `course`, `location`)

### Controller

- [x] 20. Rewrite `app/controllers/app.rb`:
  - drop `Course.setup` file-store init and the old `plugin :common_logger` (logger now lives in `config/environments.rb`)
  - nest `events` and `locations` under `courses/[course_id]`
  - use `@api_root`, `@course_route`, `@event_route`, `@location_route` locals for `Location:` response headers
  - wrap create/update/read in `rescue StandardError` → `halt 4xx`
  - use `save_changes` (keeps `rubocop-sequel` happy)

### Ops

- [x] 21. `Rakefile` with `default: :spec`, `spec`, `style`, `audit`, `release_check`, `console`, `db:{load,load_models,migrate,delete,drop}`, and `print_env` helper
- [x] 22. `rake db:drop` guards against production

### Tests

- [x] 23. `spec/spec_helper.rb` — sets `RACK_ENV=test`, loads fixtures, `wipe_database` helper
- [x] 24. `spec/test_load_all.rb` — `require_app`, `def app = Tyto::Api`, loads `rack/test` outside production
- [x] 25. Slim `spec/api_spec.rb` to root-route smoke test (resource tests move to dedicated specs)
- [x] 26. `spec/env_spec.rb` — `Tyto::Api.config.DATABASE_URL` must be `nil` (regression test for the `ENV.delete` contract)
- [x] 27. `spec/courses_spec.rb` — HAPPY list/show/create, SAD unknown id
- [x] 28. `spec/locations_spec.rb` — HAPPY list/show/create, SAD unknown id
- [x] 29. `spec/events_spec.rb` — HAPPY list/show/create, SAD unknown id

### Verify

- [x] 30. `bundle install`
- [x] 31. `rake db:migrate` (dev) + `RACK_ENV=test rake db:migrate`
- [x] 32. `rake spec` — must be green
- [x] 33. `bundle exec rubocop .` — no offenses
- [x] 34. `bundle exec bundle-audit check --update` — no vulnerabilities
- [ ] 35. Code review
- [ ] 36. Merge PR to `main`

## Completed

All implementation tasks through verification (#1–#34) are complete. Working tree is intentionally uncommitted pending code review (#35). The working tree currently shows 10 modified files and 14 new files/directories; see `git status` on this branch.

### Test results snapshot

```text
rake spec
  14 runs, 37 assertions, 0 failures, 0 errors, 0 skips

rubocop .
  19 files inspected, no offenses detected

bundle-audit check --update
  No vulnerabilities found
```

## Post-Implementation Notes (for reviewer)

1. **`sqlite3` pinned to `~>2.0`.** The older `1.x` line can't resolve cleanly on Ruby `4.0.1`.
2. **`Gemfile.lock` upgraded several transitive gems** (rubocop, sequel, minitest, etc.). Everything is green — `rake release_check` passes — so there's no reason to pin back.
3. **`Location` has no `address` column.** Matches full Tyto's schema. `2-db-hardening` will encrypt `longitude`/`latitude` rather than an address string, which lines up with the attendance-coordinate encryption story in `8-auth-scope`.
4. **`Event.location_id` is nullable** so seeds and tests can create events without tying them to a specific room. Keeps the model honest for async events later.
5. **`Course` has no `owner_id`** because there are no accounts yet. Backfilling an orphan column now would create migration debt for the account work when it lands.
6. **`spec/env_spec.rb` is the regression test for the `ENV.delete` contract.** If anyone refactors `config/environments.rb` to read `ENV[...]` directly and forgets the `.delete`, this test flips red. Please do not weaken it to `.wont_equal` or similar.
7. **`rake db:drop`** deliberately refuses to touch production. That's not load-bearing yet (no prod DB), but wiring the guard in now means we can't forget later.
8. **Nothing is committed yet.** Working tree is unstaged so you can diff. Use `git status` / `git diff` on branch `1-db-orm`.

---

Last updated: 2026-04-09
