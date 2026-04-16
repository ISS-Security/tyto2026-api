# 2-db-hardening — Secure configuration and encryption at rest

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update this plan before and after task and subtask implementations.

## Branch

`2-db-hardening`

## Goal

Harden the API against common database vulnerabilities and add encryption at rest for sensitive location coordinates. This branch introduces: mass assignment prevention, SQL injection prevention (verified via tests), UUID primary keys for user-facing entities that gate sensitive data, a `SecureDB` cryptographic library using RbNaCl SimpleBox, application logging, and a restructured test suite with SECURITY-prefixed tests for each vulnerability class.

## Strategy: Vertical Slice

1. Config + autoload — `require_app.rb`, `config/environments.rb`, `config/secrets-example.yml`, `.rubocop.yml`
2. Crypto library — `app/lib/secure_db.rb`
3. Schema — migrations for UUID + encrypted columns; seed data
4. Models — whitelist_security + encrypted getters/setters on Location; whitelist on Course, Event
5. Controller — mass assignment error handling, logging, improved error rescue
6. Ops — Rakefile updates (spec glob, `newkey:db`, db:load config loading)
7. Tests — restructure into `spec/integration/` and `spec/unit/`; add SECURITY tests

## Current State

- [ ] Plan created
- [ ] Branch created off `main`
- [ ] Config + autoload
- [ ] Crypto library (`SecureDB`)
- [ ] Schema + seeds
- [ ] Models (whitelist_security, encrypted coords)
- [ ] Controller (mass assignment handling, logging)
- [ ] Ops (Rakefile)
- [ ] Tests restructured + SECURITY tests added
- [ ] `rake spec` green
- [ ] `bundle exec rubocop .` clean
- [ ] `bundle exec bundle-audit check --update` clean
- [ ] Code review
- [ ] Retrospective migration audit
- [ ] Commits squashed to match required count (1)
- [ ] Merge to `main`

## Key Findings

### Starting point

`main` has three models (Course, Location, Event) with integer PKs, plaintext Location coordinates, flat spec directory, and Figaro-based config with `ENV.delete('DATABASE_URL')`.

### Threat model delta vs previous branch

| Risk | Addressed here | Deferred |
|---|---|---|
| Mass assignment — HTTP payloads overwrite protected columns | `whitelist_security` plugin on all models | — |
| SQL injection — user input in route params | ORM literalization already safe; verified with SECURITY tests | — |
| Sequential integer IDs — enumerable, guessable | UUID on Event (user-facing, gateway to sensitive attendance data) | — |
| Plaintext sensitive data at rest | Location coords encrypted via SecureDB (RbNaCl SimpleBox) | Attendance coords deferred per project rules |
| Secret key exposure | `DB_KEY` via Figaro (gitignored), `ENV.delete` after load | Additional keys deferred per project rules |
| No application logging | HTTP request logging + custom event logging | — |

### Domain scope (this branch only)

**Entities**: Course, Location, Event (unchanged from previous branch).

**Schema changes:**
- Location: `longitude Float` → `longitude_secure String`, `latitude Float` → `latitude_secure String`. Keeps integer PK (not user-facing in browser URLs; coords protected by encryption).
- Event: PK → UUID (user-facing, gateway to sensitive attendance data). `location_id` FK stays integer.
- Course: no schema change (public entity, integer PK)

## Questions

- [x] Q1. Which entities get UUID PKs? **Event only.** UUID rule: apply to entities whose IDs appear in user-facing browser URLs and gate sensitive data. Event qualifies (attendance URLs, student PII). Course is public. Location is not browser-facing; coords protected by encryption.
- [x] Q2. Does events migration need updating? **Yes** — Event gets UUID PK. `location_id` FK stays integer (no type mismatch).

## Scope

**In scope:**
- `SecureDB` library (RbNaCl SimpleBox encrypt/decrypt + key generation)
- Location coord encryption at rest (`longitude_secure`, `latitude_secure`)
- UUID primary key for Event (user-facing, gates sensitive data)
- Mass assignment prevention (`whitelist_security`) on all three models
- Application logging (HTTP request + custom event)
- `newkey:db` Rake task
- `DB_KEY` in secrets config
- Test restructuring: `spec/integration/` and `spec/unit/`
- SECURITY tests: mass assignment, SQL injection, UUID, encrypted attributes
- `.rubocop.yml` tightening
- `require_app.rb` `config:` kwarg
- `config/environments.rb` wrapped in `configure` block
- `spec/env_spec.rb` expanded to check `DB_KEY`

**Out of scope** (deferred per project rules):
- Account model, password hashing, email encryption
- Attendance coord encryption
- Additional secret keys (`HASH_KEY`, `MSG_KEY`)

**Parallel branch required before this week is done:**
- `2-demo-db-vulnerabilities` — intentional vulnerability demo branch, branched off `1-db-orm` (not this branch), **never merged to main**. Removes mass assignment protection and adds a raw SQL query route to demonstrate attacks before showing the hardened code.

## Security Concerns Addressed This Week

1. **Mass assignment attacks** — Sequel's `whitelist_security` plugin restricts which columns can be set via mass assignment. SECURITY tests verify HTTP-level rejection of illegal attributes.

2. **SQL injection** — Sequel's ORM methods use parameterized queries / literalization by default. SECURITY tests verify that encoded SQL fragments in URL params return 404, not leaked data.

3. **Sequential ID enumeration / IDOR** — UUID v4 (via SecureRandom) on Event makes IDs non-guessable and non-enumerable. UUID applied to entities whose IDs appear in user-facing URLs and gate sensitive data. SECURITY test verifies Event IDs are not numeric.

4. **Plaintext sensitive data at rest** — Location coordinates encrypted using RbNaCl SimpleBox (XSalsa20-Poly1305 authenticated encryption). Model provides transparent encrypt/decrypt via virtual attributes. SECURITY test verifies raw DB values differ from plaintext.

5. **Secret key management** — `DB_KEY` stored in gitignored `config/secrets.yml`, loaded via Figaro, deleted from ENV after use. Regression test ensures the key doesn't leak.

6. **Application logging** — HTTP request logging to `$stdout`, custom event logging to `$stderr`. Mass assignment attempts logged with WARN severity.

## Tasks

> Check tasks off as soon as each one is finished — do not batch.

### Setup

- [ ] 1. **`.rubocop.yml`** — Comment out blanket exclusions for `Metrics/BlockLength` on controllers and Rakefile (use inline pragmas). Comment out `Style/HashSyntax` exclusion. Verify `Style/SymbolArray` exclusion path. **`.ruby-version`** — Bump `4.0.1` → `4.0.2`. Run `bundle update` to regenerate `Gemfile.lock`.

### Config + autoload

- [ ] 2. **`require_app.rb`** — Add `config:` keyword argument (default `true`). Update default folders to include `lib`. Regenerate `Gemfile.lock` if needed.
- [ ] 3. **`app/lib/secure_db.rb`** — New: `SecureDB` class with `generate_key`, `setup`, `encrypt`, `decrypt` using RbNaCl SimpleBox.
- [ ] 4. **`config/environments.rb`** — Wrap in `configure` block. Add logger, SecureDB setup, `ENV.delete('DB_KEY')`. HTTP logging to `$stdout`, custom to `$stderr`. **`config/secrets-example.yml`** — Add `DB_KEY` entries.

### Schema + seeds

- [ ] 9. **`db/migrations/002_locations_create.rb`** — Keep integer PK. `longitude_secure`/`latitude_secure` String columns (replacing Float). **`db/migrations/003_events_create.rb`** — UUID PK. `location_id` FK stays integer.
- [ ] 10. **`db/seeds/location_seeds.yml`** — Keep coord values as strings. Add non-ASCII name for encryption edge-case testing.

### Models

- [ ] 5. **`app/models/location.rb`** — whitelist_security, encrypted getters/setters for coords, update `to_json`. No UUID (integer PK).
- [ ] 5b. **`app/models/event.rb`** — UUID plugin (Event IDs are user-facing and gate sensitive data).
- [ ] 6. **`app/models/course.rb`** — whitelist_security + allowed columns. **`app/models/event.rb`** — whitelist_security + allowed columns.

### Controller

- [ ] 7. **`app/controllers/app.rb`** — Mass assignment rescue (`Sequel::MassAssignmentRestriction` → 400), logging, improved error handling on all POST routes.

### Ops

- [ ] 8. **`Rakefile`** — Spec pattern `spec/**/*_spec.rb`. db:load loads config. `newkey:db` namespace. Inline rubocop pragmas.

### Tests

- [ ] 11. **Restructure** — `spec/integration/` and `spec/unit/` dirs. Move existing specs.
- [ ] 12. **Integration specs** — Update require_relative paths. Add SECURITY mass assignment tests to events and locations specs.
- [ ] 13. **`spec/integration/api_courses_spec.rb`** — Split/restructure from existing. Add SECURITY mass assignment + SQL injection tests.
- [ ] 14. **Unit specs** — `spec/unit/locations_spec.rb` (data round-trip, encrypted attrs). `spec/unit/events_spec.rb` (data round-trip, UUID non-determinism).
- [ ] 15. **`spec/unit/secure_db_spec.rb`** — Encrypt, decrypt ASCII, decrypt non-ASCII.
- [ ] 16. **`spec/env_spec.rb`** — Add `DB_KEY` check.

### Verify

- [ ] `rake spec` — all tests pass
- [ ] `bundle exec rubocop .` — clean
- [ ] `bundle exec bundle-audit check --update` — clean
- [ ] Code review
- [ ] Retrospective migration audit
- [ ] Squash / split into required commit count
- [ ] Merge PR to `main`
- [ ] Create parallel `2-demo-db-vulnerabilities` branch off `1-db-orm` (never merged to main)
- [ ] Skill self-reflection

## Commit strategy

- **Required commit count**: 1 (adapted from the reference branch's 2 commits, consolidated per plan)
- **Subject**: `Hardens database and secures configuration`
- **Body**: Tyto-specific bullets summarizing all changes

## Completed

(to be filled in during implementation)

## Post-Implementation Notes (for reviewer)

(to be filled in before handing off for review)

---

Last updated: 2026-04-16
