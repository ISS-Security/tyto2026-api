# 9-signed-requests — Digital request signing + admin accounts index

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update this plan before and after task and subtask implementations.
>
> **FINAL RELEASE**: This is the last feature branch. After it merges, the API is feature-locked — security updates only. Out-of-scope items are permanently out.

## Branch

`9-signed-requests`

## Goal

Unauthenticated routes (`POST /accounts`, everything under `/auth/*`) currently accept any well-formed JSON body — there is no auth token yet at that point in the flow, so the API cannot tell a trusted client app from an arbitrary script. This branch requires those requests to be digitally signed (Ed25519 via RbNaCl): the client signs the body with its private `SIGNING_KEY`; the API verifies with the public `VERIFY_KEY` and rejects anything unsigned or forged with 403. Authenticated routes are unchanged (bearer tokens already carry trust).

Also adds an admin-only accounts index — `GET /api/v1/accounts` with server-side role filtering and sorting — so admins can inventory accounts and pivot into the existing per-account role-management routes.

## Strategy: Vertical Slice

1. `SignedRequest` lib (keypair generation, sign, verify, parse) + unit spec
2. Config wiring (`environments.rb`, secrets, `rake newkey:signing`)
3. Controller enforcement (`auth.rb` route-wide, `accounts.rb` POST)
4. Integration specs sign their requests; new unsigned-request rejection tests
5. Admin accounts index route + policy gate + specs

## Current State

- [x] Plan created
- [x] Branch created off `main`
- [x] `SignedRequest` lib + unit spec
- [x] `rake newkey:signing` + Rakefile `:load_libs` refactor
- [x] Config + secrets wiring (+ local `secrets.yml` keys — user action)
- [x] `auth.rb` route-wide signed-request gate
- [x] `accounts.rb` POST signed body + tightened error handling
- [x] `http_request.rb#signed_body_data`
- [x] Integration + env specs updated
- [x] Admin accounts index + accounts scope-gating fix + specs
- [x] Code review — reviewed and approved 2026-06-04
- [x] Commits shaped to required count (2 payloads)
- [ ] Merge PR to `main` — deferred to user, done manually later in the week after class

## Key Findings

### Starting point

- `auth.rb` has three `routing.is` blocks (authenticate / register / sso), each reading `HttpRequest.new(routing).body_data` separately — all collapse to one route-top `@request_data = ...signed_body_data` with a 403 rescue.
- `POST /auth/sso` takes `{id_token:}` — the signed wrapper goes around that same body; routes read `@request_data[:id_token]`.
- `accounts.rb` POST still uses the early `Account.new`/`save_changes` shape; this branch moves it to `Account.create` with explicit rescues (mass assignment → 400, unverified signature → 403, unknown → 500).
- `http_request.rb#body_data` has an empty-body guard — keep it; `signed_body_data` wraps it.
- Crypto libs are namespaced (`Tyto::SecureDB`, `Tyto::AuthToken`); `SignedRequest` follows.
- `spec/env_spec.rb` asserts secrets are scrubbed from `Api.config` — must gain `SIGNING_KEY`/`VERIFY_KEY` cases; never weaken it.
- Policies + role predicates exist for all resources; the new index route is gated through the policy layer like every other route, not an ad-hoc check.

### Threat model delta

| Risk | Addressed here | Out |
| --- | --- | --- |
| Tampered/forged bodies on unauthenticated routes | Ed25519 signature verification, 403 on failure | — |
| Arbitrary clients driving registration/auth | Only holders of `SIGNING_KEY` produce acceptable requests | Multi-client key registry |
| Replay of captured signed requests | — | Documented caveat; not implemented |
| No admin account inventory | Admin-only `GET /accounts` (token + policy gated) | — |
| Leaked READ_ONLY key can mutate system roles (pre-existing, found at plan time) | `AccountPolicy` write predicates gated on `can_write?('accounts')`; scope threaded through `SystemRolePolicy`/`AssignSystemRole` | — |

### Domain scope (this branch only)

No schema changes, no new entities. `SignedRequest` is a crypto library. The index reads existing `Account` + `system_roles`.

## Questions

- [x] Q1. Policy placement for the index → **`AccountPolicy`** (decided 2026-06-04). `SystemRolePolicy` exists but is target-scoped (`viewer, target_account`) for role assign/revoke — wrong shape for a collection index; it already delegates its actor half to `AccountPolicy` anyway. `AccountPolicy` has all the pieces: `is_admin?`, `AccountPolicy::AdminScope#viewable`, `index_summary`. Implementation: thin `can_index_all?` (delegates to `is_admin?`) gates the route → 403 first (do not rely on `AdminScope`'s filter semantics, which would return `[self]` for non-admins), then `AdminScope` supplies the dataset.
- [x] Q2. Should a `READ_ONLY`-scoped token get the index? → **Yes** (decided 2026-06-04). Matches the codebase-wide convention: every policy composes scope ∧ role — reads gate on `can_read?(RESOURCE)`, writes independently on `can_write?(RESOURCE)`. So `can_index_all? = auth_scope.can_read?('accounts') && is_admin?` — a READ_ONLY key minted for an admin can list, never mutate.
- [x] Q4. Key distribution (decided 2026-06-04): **this API never holds the client app's private key.** The reference layout put both keys in every environment, letting a test convenience bleed into production and undermining non-repudiation. Tyto topology: dev → `VERIFY_KEY` only (pairs with the client app's dev `SIGNING_KEY`); test → a *dedicated test keypair, both halves* (specs forge client signatures with throwaway keys); production → `VERIFY_KEY` only. Code consequence: `SignedRequest.setup(verify_key64, signing_key64 = nil)` — signing half optional; `.sign` raises `KeypairError` when unconfigured, so the production API physically cannot sign.
- [x] Q3. **Scope gap found while answering Q2** (decided 2026-06-04: fix in this branch, folded into the index commit). `AccountPolicy`/`SystemRolePolicy`/`AssignSystemRole` take no `auth_scope`, so the system-role PUT/DELETE routes never scope-check — an admin's leaked READ_ONLY key (minted by `GET /accounts/[username]`) can mutate system roles, violating the scope library's "leaked READ_ONLY key can never mutate" guarantee. The gating spec has no ACCOUNT cases, which is why it went uncaught. Tasks 17–18.

## Scope

**In scope**: `SignedRequest` lib; `newkey:signing`; signing enforcement on `POST /accounts` and `/auth/*`; spec updates; admin accounts index (`?role=`, `?sort=username|role`, 403 non-admin).

**Out of scope** (feature set is final — these are permanently out):

- Replay protection (nonce/timestamp in signed payloads)
- Registry of multiple client signing keys
- Signed responses (server → client)
- Pagination on the accounts index

## Security Concerns Addressed This Week

1. **Authenticating the API client** — token-bearing routes implicitly trust the bearer; pre-login routes had nothing. Digital signatures close the gap.
2. **Signing vs encryption** — signatures give integrity + non-repudiation; the private key never leaves the client's server; the API holds only the public key.
3. **Ed25519 keypairs via RbNaCl** — asymmetric keys built for signing; provisioned with `rake newkey:signing`.
4. **Explicit trust boundaries** — every route now declares its trust source: auth token, or signature.

## Tasks

> Check tasks off as soon as each one is finished — do not batch.

### Commit 1 — signed requests

#### Lib + config

- [x] 1. `app/lib/signed_request.rb` — `Tyto::SignedRequest`: `VerificationError`, `KeypairError`, `.setup(verify_key64, signing_key64 = nil)` (signing half **optional** per Q4 — only the test env configures it), `.generate_keypair`, `.parse(signed)`, `.sign(message)` (test-only; raises `KeypairError` when no signing key configured), `.verify(message, signature64)`. Base64-strict throughout.
- [x] 2. `spec/unit/signed_request_spec.rb` — round-trip sign/verify; forged signature → `VerificationError`; bad keypair → `KeypairError`; generated keys decode to 32 bytes; `.sign` raises `KeypairError` after verify-only setup (Q4).
- [x] 3. `config/environments.rb` — require the lib; `SignedRequest.setup(ENV.delete('VERIFY_KEY'), ENV.delete('SIGNING_KEY'))`.
- [x] 4. `config/secrets-example.yml` — per Q4 topology: development → `VERIFY_KEY` only (pairs with the client app's dev `SIGNING_KEY`); test → `SIGNING_KEY` + `VERIFY_KEY` (dedicated test keypair for spec-forged signatures); production → `VERIFY_KEY` only (private key lives only in the client app's config). Placeholder convention, no literal keys.
- [x] 5. ~~USER ACTION~~ *(delegated to AI 2026-06-04)*: run `rake newkey:signing` twice — (a) dev keypair: `VERIFY_KEY` → this repo's dev `secrets.yml`, `SIGNING_KEY` → the client app's dev secrets; (b) test keypair: both halves → this repo's test `secrets.yml`. Production keypair generated at deploy time and split the same way. Nothing committed.
- [x] 6. `Rakefile` — `newkey` namespace: shared `task(:load_libs)` prerequisite; `db`/`hash`/`msg` depend on it (drop inline `require_app` calls); new `newkey:signing` printing `SIGNING_KEY:` and `VERIFY_KEY:` (aligned output).

#### Controllers

- [x] 7. `app/controllers/http_request.rb` — add `signed_body_data` → `SignedRequest.parse(body_data)`.
- [x] 8. `app/controllers/auth.rb` — route-top signed-body read; `SignedRequest::VerificationError` → 403 `'Must sign request'`; authenticate/register/sso blocks consume `@request_data`; keep existing per-route rescues.
- [x] 9. `app/controllers/accounts.rb` — POST reads `signed_body_data`; `Account.create`; rescues: mass assignment → 400, verification failure → 403, unknown → 500.

#### Tests

- [x] 10. `spec/integration/api_accounts_spec.rb` — sign account-creation posts; add `BAD SIGNED_REQUEST: should not accept unsigned requests` → 403; rename mass-assignment test to `BAD MASS_ASSIGNMENT: ...`.
- [x] 11. `spec/integration/api_auth_spec.rb` — sign authenticate (happy + bad password) and sso posts.
- [x] 12. `spec/env_spec.rb` — `SIGNING_KEY` and `VERIFY_KEY` must be nil in `Api.config`.
- [x] 13. Sweep every other spec that POSTs to `/auth/*` or `POST /accounts` (auth-scope, registration, SSO specs) — all must sign.

### Commit 2 — admin accounts index

- [x] 14. `accounts.rb` — `GET /api/v1/accounts` (collection root): 401 without bearer token; 403-gated via new `AccountPolicy#can_index_all?` (per Q1; Q2 decides token-scope rule), dataset via `AccountPolicy::AdminScope`; returns all accounts with `system_roles` in each `include` block.
- [x] 15. Server-side `?role=<admin|creator|member|none>` filter and `?sort=<username|role>`. **Contract (fixed at plan time with the client app)**: `none` is a reserved filter token, never looked up in the roles table — it selects accounts with zero system-role assignments.
- [x] 16. Specs: happy admin list; role filter incl. `none`; both sorts; admin READ_ONLY token can list (Q2); non-admin → 403; no token → 401.
- [x] 17. Scope-gap fix (Q3): thread `auth_scope:` into `AccountPolicy` (default `AuthScope.new`, like the other policies); reads (`can_view?`, `can_index_all?`) gate on `can_read?('accounts')`, writes (`can_edit?`, `can_delete?`, `can_assign_role?`, `can_revoke_role?`, `can_manage_system_roles?`) on `can_write?('accounts')`; thread scope through `SystemRolePolicy`, `AssignSystemRole`, and the system-role PUT/DELETE routes in `accounts.rb` (scope from `@auth.scope`, as in `courses.rb`).
- [x] 18. `spec/policies/auth_scope_gating_spec.rb` — ACCOUNT cases mirroring the existing resources: READ_ONLY admin key can view/index but cannot assign/revoke; FULL restores writes. Route-level regression in `api_accounts_spec.rb`: system-role PUT with a READ_ONLY bearer token → 403.

### Verify

- [x] `bundle exec rake spec`
- [x] `bundle exec rubocop .`
- [x] `bundle exec bundle-audit check --update`
- [x] Code review
- [x] Retrospective migration audit: diff-level, full-tree, and shared-file content diff against the reference branch — reconcile every difference
- [x] Squash / split into required commit count
- [ ] Merge PR to `main` — deferred to user, done manually later in the week after class
- [x] Skill self-reflection: re-read `/week-plan` SKILL.md and propose refinements if the week surfaced any gaps

## Commit strategy

- **Required payload count**: **2**
  1. `Requires signed requests for non-authenticated routes` — tasks 1–13.
  2. `feat: add admin-only accounts index with role filter and sort` — tasks 14–18; commit body calls out the folded scope-gating security fix (Q3) explicitly.
- The plan commit (`docs: plan 9-signed-requests`) does not count.

## Completed

- 2026-06-04 — Commit 1 (tasks 1–13), TDD red-green throughout:
  - `Tyto::SignedRequest` with the Q4 key topology (signing half optional;
    `.sign` raises `KeypairError` when unconfigured — production physically
    cannot sign). Unit spec: 6 tests covering round-trip, forged signature,
    tampered data, missing signature, bad keypair, verify-only `.sign`
    refusal. The spec snapshots/restores the class-level keys around each
    test so the config-loaded test keypair survives for integration specs.
  - Route-top signed-body gate in `auth.rb` (403 `Must sign request`);
    `accounts.rb` POST moved to `Account.create` + explicit rescues;
    `http_request.rb#signed_body_data`; Rakefile `:load_libs` prerequisite
    + `newkey:signing`.
  - Spec sweep: no unsigned `/auth/*` or `POST /accounts` call sites remain;
    `env_spec` pins `SIGNING_KEY`/`VERIFY_KEY` scrubbing.
- 2026-06-04 — Commit 2 (tasks 14–18), TDD red-green:
  - Scope-gap fix (Q3) first: `AccountPolicy` gains `RESOURCE = 'accounts'`
    + `auth_scope:`; reads gate on `can_read?`, writes on `can_write?`;
    scope threaded through `SystemRolePolicy`, `AssignSystemRole`, and the
    system-role PUT/DELETE routes. Route-level READ_ONLY regressions were
    confirmed RED against the old code (the leaked-key mutation reproduced)
    before going GREEN.
  - Admin index extracted into a `ListAccounts` service per the house
    pattern — the route just 401s, calls the service, and maps
    `ForbiddenError` → 403. Filter/sort live in `AdminScope#viewable`:
    `none` reserved token; `sort=role` orders by primary-role precedence
    (admin > creator > member > role-less) with username tie-break. The
    role-sort spec seeds a late-created second admin to defeat
    insertion-order coincidence.
- 2026-06-04 — Style chores (post-review, repo convention): chained calls
  and method arguments both indent one step (`.rubocop.yml`
  `Layout/MultilineMethodCallIndentation: indented`,
  `Layout/ArgumentAlignment: with_fixed_indentation`); all existing sites
  autocorrected; suite re-verified green after each.
- Verified: 269 runs / 595 assertions, 0 failures; rubocop clean
  (105 files); bundle-audit clean.

## Post-Implementation Notes (for reviewer)

- **Key topology is a deliberate deviation from the reference layout**
  (which shipped both key halves in every environment): dev/production hold
  `VERIFY_KEY` only; test holds a dedicated throwaway keypair so specs can
  forge client signatures. Non-repudiation preserved — the signing key never
  exists on the API side outside test.
- **Retrospective migration audit (2026-06-04)**: file lists reconcile
  against the reference branch; Tyto-only additions are the unit spec for
  the signing lib and the `env_spec` scrubbing cases (test-depth rule).
  A redundant `require_app` inside the reference `newkey:msg` task was
  dropped (noted in the payload commit body). No commented reference blocks
  were removed.
- **`?role=<unknown>` returns an empty list** (not 400) — the client app
  only emits the four contract tokens; documenting rather than validating
  keeps the route thin. Flag if a 400 is preferred.
- `AuthorizeAccount` (account detail GET) still constructs `AccountPolicy`
  without threading the caller's scope — reads are permitted under both
  scopes, so behavior is unchanged; left untouched to keep the payload
  minimal.

---

Last updated: 2026-06-04 (finalized; remaining: PR + merge by the user)
