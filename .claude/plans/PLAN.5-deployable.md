# 5-deployable — Production database deploy

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update this plan before and after each task.

## Branch

`5-deployable`

## Goal

Make the API deployable to a Heroku-style platform: pin Ruby in the Gemfile, add the `pg` gem in a `:production` group, ship a `Procfile`, expand the README to cover the operational surface, and apply small cosmetic tweaks rolled in alongside the deploy work.

The TLS/HTTPS enforcement layer (`HttpRequest#secure?`, `SECURE_SCHEME` config) was already wired up in the previous branch, so this branch is narrower than its name suggests — the work here is specifically about making the existing code production-deployable, not about adding new security surface.

## Strategy: Vertical Slice

This is a config + dependency layer change, not a feature slice. Order:

1. Gemfile (Ruby pin + production group with `pg`)
2. Procfile (process declaration for the PaaS)
3. Bundler local-without-production config (so dev installs stay lean)
4. Rakefile micro-fix (rubocop preference on `print_env`)
5. README expansion (operational instructions)
6. Cosmetic controller tweaks (message text, unused require, diagnostic puts handling)
7. Spec alignment if controller cosmetic decisions affect assertions
8. Run green-bar

## Current State

- [x] Plan created
- [ ] Branch created off `main`
- [ ] Gemfile: pin Ruby + `:production` group with `pg`
- [ ] `bundle config set --local without 'production'`
- [ ] Procfile created
- [ ] Rakefile `print_env` fetch tweak
- [ ] README operational sections audit / expansion
- [ ] `accounts.rb`: response message tweak
- [ ] `app.rb`: drop unused require
- [ ] `auth.rb` cosmetic decision (Q2)
- [ ] `api_auth_spec.rb` alignment (Q2)
- [ ] `rake spec` green
- [ ] `bundle exec rubocop .` clean
- [ ] `bundle audit check --update` clean
- [ ] Code review
- [ ] Retrospective migration audit
- [ ] Squashed to required commit count
- [ ] Merge PR to `main` — deferred to user, manual, post-class

## Key Findings

### Starting point

`main` is at the merged `4-authenticate`. Already in place:

- `SECURE_SCHEME` config in `secrets-example.yml` (HTTP for dev/test, HTTPS for production)
- `HttpRequest#secure?` halts 403 on scheme mismatch at the request boundary
- Multi-route controllers (`accounts.rb`, `auth.rb`, `courses.rb`)
- Rakefile `:load` / `:load_models` task split with `@app` reference (already in the post-deployable shape)
- Ruby 4.0.2 pinned in `.ruby-version`

The API is functionally TLS-enforced; what's missing is the production database layer and the operational deployment surface.

### Threat model delta vs previous branch

| Risk | Addressed here | Deferred |
|---|---|---|
| Production runs on dev-grade SQLite | `:production` group adds `pg`; `DATABASE_URL` honored via Sequel | PaaS provisioning + `heroku addons:create` (operational, not code) |
| Process model on a PaaS unspecified | `Procfile` declares the web process | dyno scaling / autoscale config |
| **Failed-login username enumeration via stdout logs** | `auth.rb` `UnauthorizedError` rescue switches from `puts [e.class, e.message]` (leaks typed username via `e.message` → stdout → `heroku logs`) to `Api.logger.warn('Authentication failed: invalid credentials')` (stderr, no username). Becomes critical at deploy time because stdout is externalized by the PaaS. | Audit other puts/log sites in the codebase for similar leaks — none currently identified |
| Plain HTTP in production | already enforced by `HttpRequest#secure?` | n/a |

### Domain scope (this branch only)

No new entities or fields. Pure deployability layer.

## Questions

> Crossed off as decisions are made.

- [x] **Q1. Payload commit subject — RESOLVED: `Enables production database deploy`** (Tyto-truthful normalization).
- [x] **Q2. `auth.rb` diagnostic puts — RESOLVED: replace with stderr-bound logger.warn that omits the username.** This is **not** cosmetic — it's an info leak. `UnauthorizedError#message` returns `"Invalid credentials for: #{credentials[:username]}"`, so the previous `puts [e.class, e.message]` writes the typed username to stdout. On Heroku, stdout → `heroku logs` → potentially externalized to log aggregators, allowing username enumeration and exposing typo-PII. Replace with `Api.logger.warn('Authentication failed: invalid credentials')` (no username; goes to stderr via `LOGGER = Logger.new($stderr)`). Flip the two `assert_output(/invalid/i, '')` wrappers in the spec to `assert_output('', /invalid/i)`.
- [x] **Q3. README content — RESOLVED: mention.** `bundle config set --local without 'production'` appears in the README install section.

## Scope

**In scope:**

- Gemfile: pin Ruby version, add `pg` in `:production`
- `bundle config` for local-without-production
- `Procfile`
- README operational expansion
- Tiny Rakefile rubocop fix
- `accounts.rb` 201-response message text
- `app.rb` unused `require 'logger'` removal
- (Pending Q2) `auth.rb` puts + spec assertion alignment

**Out of scope (deferred per project rules):**

- HSTS, redirect-http-to-https, browser security headers
- Token-based authorization
- Geo-validated attendance
- App-side admin UI for system roles
- Encrypted attendance coordinates

## Security Concerns Addressed This Week

(From the lecture deck for week 11.)

1. **Production-grade database.** SQLite is a development convenience; Postgres is the production target. Adding `pg` only in the `:production` bundler group keeps local installs lean and avoids forcing students to install libpq locally.
2. **Process model on a PaaS.** A `Procfile` makes the web process declarable and reproducible across dev, CI, and prod. The `puma -t 5:5` thread tuning is a teachable default — concurrency vs memory.
3. **Bundler hygiene for production secrets.** `bundle config set --local without 'production'` is the local escape hatch so dev/test never resolve `pg`. Pairs with `.bundle/config` being gitignored. The footgun is the inverse — production must NOT carry that config, or the deploy will skip `pg`.
4. **Logging hygiene at the deployment boundary.** A diagnostic `puts` line in the auth `UnauthorizedError` rescue, introduced in a previous branch as a stdout-vs-stderr teaching demo, becomes an info leak the moment we deploy. `e.message` contains the failed-login username; stdout flows into `heroku logs` and (depending on configuration) into log-aggregation services. Switching to `Api.logger.warn('Authentication failed: invalid credentials')` keeps the event logged but drops the username — stops both username enumeration and typo-PII exposure.
5. **TLS enforcement (already in place).** The lecture's HTTPS-redirect / HSTS slides describe the App-side concern. The API enforces TLS at the request boundary already; what changes here is making that production-deployable, not the enforcement itself.

## Tasks

### Setup

- [ ] 1. Verify `main` is clean. Confirm last commit on `main`.
- [ ] 2. Create branch `5-deployable` off `main`.
- [ ] 3. Commit this plan: `docs: plan 5-deployable`.

### Gemfile / dependencies

- [ ] 4. Add `ruby File.read('.ruby-version').strip` to `Gemfile` immediately after the `source` line.
- [ ] 5. Add a `group :production do gem 'pg' end` block. Place it near the `# Database` section.
- [ ] 6. Run `bundle config set --local without 'production'` **before** `bundle install`. `pg` requires libpq, which isn't installed locally; without this config, `bundle install` will fail. Confirm `.bundle/config` is gitignored.
- [ ] 7. Run `bundle install`. The lockfile records `pg`'s metadata for the resolver but the gem is not installed locally.

### Process model

- [ ] 8. Create `Procfile` at repo root with one line: `web: bundle exec puma -t 5:5 -p ${PORT:-3000} -e ${RACK_ENV:-development}`.

### Rakefile

- [ ] 9. Tweak `print_env` to use `ENV.fetch('RACK_ENV', nil) || 'development'` instead of `ENV['RACK_ENV'] || 'development'` (rubocop preference).

### Controllers (cosmetic + Q2 leak fix)

- [ ] 10. `app/controllers/accounts.rb`: change the 201 response body's `'Account saved'` to `'Account created'`.
- [ ] 11. `app/controllers/app.rb`: remove the unused `require 'logger'` line.
- [ ] 12. **`app/controllers/auth.rb` info-leak fix (Q2).** Replace `puts [e.class, e.message].join(': ')` in the `UnauthorizedError` rescue with `Api.logger.warn('Authentication failed: invalid credentials')`. Drop the `=> e` capture since `e` is no longer referenced. This stops the typed username (carried in `e.message`) from reaching stdout and, by extension, externalized PaaS logs.

### Specs

- [ ] 13. **`spec/integration/api_auth_spec.rb` (Q2).** Flip the two `assert_output(/invalid/i, '')` wrappers — in the "invalid password" and "unknown username" specs — to `assert_output('', /invalid/i)` (empty stdout, `invalid` on stderr). Update both test descriptions from `... and log to stdout (no stderr)` to `... and log to stderr (no stdout)`.

### README

- [ ] 14. Audit existing README sections (Test, Execute, Release-check are already present from earlier branches). Add what's missing:
   - `bundle config set --local without 'production'` instruction in the Install section.
   - Brief mention of `git push heroku main` and `heroku run rake db:migrate` for first-deploy onboarding. (Optional — could live in a separate ops doc.)

### Verify

- [ ] 15. `rake spec` — all green.
- [ ] 16. `bundle exec rubocop .` — clean.
- [ ] 17. `bundle exec bundle-audit check --update` — clean.
- [ ] 18. Smoke run: `bundle exec rake run:dev`; curl `/api/v1/courses` locally; confirm dev TLS gate (`SECURE_SCHEME: HTTP`) still works.
- [ ] 19. Code review.
- [ ] 20. Retrospective migration audit (diff-level, full-tree, shared-file content diff). Reconcile every difference.
- [ ] 21. Squash to the required payload-commit count.
- [ ] 22. Merge PR to `main` — deferred to user, manual, post-class.
- [ ] 23. Skill self-reflection — re-read the week-plan skill and propose refinements if any gap surfaced.

## Infrastructure setup (user-only — AI provides guidance, never executes)

> **Rule:** Cloud-infrastructure setup is the user's responsibility. The AI does **not** run `heroku create`, `heroku addons:create`, `heroku config:set`, `git push heroku`, `heroku run`, `heroku restart`, or any other command that creates, modifies, or pays for cloud resources. The AI documents what needs provisioning, explains trade-offs, and drafts copy-pastable commands; the user runs them.

The list below is reference material the user works from.

| Step | Notes |
|---|---|
| Create a Heroku account (or chosen PaaS account); install the CLI; upload your SSH public key | One-time setup. `brew install heroku/brew/heroku` on macOS; `heroku keys:add ~/.ssh/id_ed25519.pub` (or your chosen key). |
| `heroku create <api-app-name>` | Creates a Heroku app and adds a `heroku` git remote. The API and the App get **separate** Heroku apps. |
| `heroku addons:create heroku-postgresql:essential-0` | Free/cheap-tier Postgres add-on. Older slides reference `hobby-dev`; that tier was retired — `essential-0` (or `mini`) is current. |
| `heroku config:set DB_KEY=... HASH_KEY=... SECURE_SCHEME=HTTPS LANG=en_US.UTF-8` | Production env vars. Generate fresh keys via `rake newkey:db` and `rake newkey:hash` and copy the values. **Do not reuse dev keys.** |
| `git push heroku main` | First deploy. Heroku detects the Ruby app from `config.ru`. |
| `heroku run rake db:migrate` | Run migrations against the provisioned Postgres. |
| `heroku restart` | Pick up the new schema. |
| Smoke: `curl https://<api-app>.herokuapp.com/api/v1/courses` over HTTPS, then over HTTP | Confirm 200 over HTTPS, 403 over HTTP (the TLS gate from the previous branch). |

**The user runs all of the above. The plan covers only the code changes that make them work; the AI never executes infrastructure commands.**

## Commit strategy

- **Required commit count**: 1 payload commit.
- **Subject**: `Enables production database deploy`.
- **Grouping**: everything in scope folds into the single payload commit. The plan-doc commits (the initial `docs: plan 5-deployable` plus any plan-only follow-ups) are scaffolding and do not count toward the payload total — they fold into the plan commit at finalize.
- **Body should call out** the Q2 info-leak fix as a deliberate security cleanup co-located with the deploy work, not just a cosmetic noise change.

## Completed

(filled in during implementation)

## Post-Implementation Notes (for reviewer)

(filled in before handoff)

---

Last updated: 2026-05-07
