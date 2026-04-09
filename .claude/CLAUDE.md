# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`tyto2026-api` is the JSON Web API for Tyto, an attendance-tracking app. It manages courses, events, locations, and (in later weeks) accounts, enrollments, and attendance records with geofencing.

The repo follows a branch-by-branch progression where each numbered branch introduces new functionality and a new security concern. Branches are merged weekly into `main`.

- **Language/runtime:** Ruby 4.0.1
- **Framework:** Roda
- **ORM:** Sequel
- **Database:** SQLite for development/test (production DB planned for a later branch)
- **Config/secrets:** Figaro (`config/secrets.yml`, gitignored)
- **Crypto:** RbNaCl (introduced in a later branch)
- **Testing:** Minitest + minitest-rg + rack-test

## Commands

- **Install dependencies:** `bundle install`
- **Setup dev database (once):** `rake db:migrate`
- **Setup test database (once):** `RACK_ENV=test rake db:migrate`
- **Run server:** `puma`
- **Run tests:** `rake spec`
- **Lint:** `bundle exec rubocop .`
- **Audit dependencies:** `rake audit`
- **Full release check:** `rake release_check` (spec + style + audit)
- **Console (Pry REPL with app loaded):** `rake console`
- **Wipe database rows (keeps schema):** `rake db:delete`
- **Drop local db file (refuses in production):** `rake db:drop`

## Architecture

### Layout

```text
.
├── Gemfile / Gemfile.lock
├── Rakefile
├── require_app.rb          # autoloader for config / app/models / app/controllers
├── config.ru
├── config/
│   ├── environments.rb     # Figaro + Sequel connection, ENV.delete('DATABASE_URL')
│   ├── secrets.yml         # gitignored — real dev/test DB URLs
│   └── secrets-example.yml # committed template
├── app/
│   ├── controllers/app.rb  # Roda routing tree
│   └── models/             # Sequel::Model classes
├── db/
│   ├── migrations/         # Sequel migrations (001_, 002_, ...)
│   ├── seeds/              # YAML fixtures
│   └── local/              # SQLite files (gitignored)
└── spec/
    ├── spec_helper.rb
    ├── test_load_all.rb
    ├── api_spec.rb
    ├── env_spec.rb
    ├── courses_spec.rb
    ├── locations_spec.rb
    └── events_spec.rb
```

### Module namespace

All app classes live under `Tyto`. The Roda app is `Tyto::Api`.

### Routing

REST routes are versioned under `api/v1/...` with nested resources:

- `GET/POST /api/v1/courses`
- `GET /api/v1/courses/[course_id]`
- `GET/POST /api/v1/courses/[course_id]/events`
- `GET /api/v1/courses/[course_id]/events/[event_id]`
- `GET/POST /api/v1/courses/[course_id]/locations`
- `GET /api/v1/courses/[course_id]/locations/[location_id]`

JSON response envelope:

```json
{ "data": { "type": "...", "attributes": { ... } }, "included": { ... } }
```

### Data store

Sequel models with `one_to_many` / `many_to_one` associations. `Course` cascades destroys to its events and locations via `plugin :association_dependencies`. The `DB` constant lives on `Tyto::Api` and is reached via `Tyto::Api.DB`.

### Environments

`ENV['RACK_ENV']` drives everything (`development` / `test` / `production`). `spec/spec_helper.rb` sets `RACK_ENV=test` as the very first statement. Figaro reads `config/secrets.yml` per environment; production reads from real host env vars.

### Test conventions

- Minitest with `minitest-rg` colored output and `rack-test` HTTP helpers
- `spec/spec_helper.rb` defines `wipe_database` and loads seed YAML into a `DATA` hash
- Each resource spec wipes the DB in a `before` block
- Tests are labeled `HAPPY:` (valid input, expected path) / `SAD:` (bad input, error path) / `BAD:` (something breaks)
- `spec/env_spec.rb` is the regression test that secret env vars are not exposed through `Tyto::Api.config`

## Style

RuboCop with `rubocop-minitest`, `rubocop-performance`, `rubocop-rake`, `rubocop-sequel` plugins. Target Ruby version 4.0. New cops enabled.

- `Metrics/BlockLength` excluded for `app/controllers/*.rb`, `spec/**/*`, `Rakefile`
- `Security/YAMLLoad` enforced outside `spec/**/*`
- `Style/HashSyntax` / `Style/SymbolArray` excluded for `Rakefile` and `db/migrations/*.rb`
- All documentation markdown files must be kept lint-free (no trailing whitespace, consistent heading levels, blank lines around blocks, etc.)

## Security conventions (project-wide)

These rules apply to every branch; violations should be flagged in review.

- **Never commit `config/secrets.yml`.** It is gitignored. Use `config/secrets-example.yml` as the committed template.
- **Never touch `config/secrets.yml` from automation** — it holds the real local DB URL (and, in later branches, real crypto keys).
- **Secrets never live in `ENV` longer than necessary.** `config/environments.rb` reads sensitive vars via `ENV.delete(...)` so downstream gems and subprocesses cannot see them. `spec/env_spec.rb` guards this contract.
- **All SQL must go through Sequel.** No string-concatenated queries.
- **YAML loading must use `YAML.safe_load_file`.** If a fixture legitimately needs a non-primitive class, allowlist it explicitly via `permitted_classes:`.
- **`rake release_check` must stay green before merging any branch to `main`.** It runs spec + style + audit; a failing audit blocks release.
- **Never run `git add` / `git commit` in this repo without explicit approval.**
- **Respect branch scope.** Features and security concerns that belong to later branches per the project rules must not creep into the current one.
