# 8-auth-scope — Token-embedded AuthScope + geo-validated attendance

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update this plan before and after task and subtask implementations.

## Branch

`8-auth-scope` — branched off the `7-policies` tip (not `main`, which is
still behind). The follow-on SSO branch will build on this branch's tip.

## Goal

Introduce OAuth-style **authorization scopes** carried inside the
encrypted auth token (`AuthScope`, `resource:permission` syntax with a `*`
wildcard) and make every Policy object check scope *before* its
role/ownership logic. Then add **geo-validated attendance**: a student can
only check in when they are at the right *time* (already enforced via
`event.live_now?`) **and** the right *place* (proximity to the event's
location), with the student's submitted coordinates **encrypted at rest**.

Adapted from the project's reference API at the corresponding branch,
extended with the attendance geo-eligibility + coordinate-encryption work.

## Strategy: Vertical Slice

1. `AuthScope` library (`resource:permission`, `*` wildcard, `can_read?`/`can_write?`).
2. Auth token carries a `scope`; default web-app login token is full
   (`*:write`); the account-detail token is read-only (`*:read`).
3. `AuthorizedAccount` model + `AuthorizeAccount` service wrap (account, scope).
4. Every policy gains an `auth_scope` param and gates predicates on
   `can_read?`/`can_write?` for its resource.
5. Thread scope controller → service → policy at every call site.
6. Geo-attendance: encrypted coordinate columns, an eligibility check
   (time + Haversine distance), and teaching-staff management routes.

## Current State

- [ ] Plan created
- [ ] Branch created
- [ ] `AuthScope` lib + spec
- [ ] Auth token scope plumbing
- [ ] `AuthorizedAccount` + `AuthorizeAccount`
- [ ] Scope threaded through all policies
- [ ] Account-detail endpoint returns a read-only-scoped token
- [ ] Attendance coordinate migration (additive)
- [ ] Eligibility (time + Haversine) + encrypted coords
- [ ] Teaching-staff attendance management routes
- [ ] `rake spec` green / rubocop / bundler-audit
- [ ] Code review
- [ ] Retrospective migration audit
- [ ] Squash to required commit count
- [ ] Merge PR to `main` — deferred to user, after class

## Key Findings

### Starting point

- `AuthToken` is `AuthToken.new(payload, expiration)` / `AuthToken.load(token)`.
  The payload is the account envelope merged with the internal `id`.
  **No scope field today** — this branch adds one.
- `http_request.rb#authenticated_account` returns the decrypted payload
  hash; `app.rb` sets `@auth_account` from it; controllers read
  `@auth_account.dig('attributes','id')` then `Account.first(id: …)`.
- Policies (`course/event/location/attendance/account/enrollment/system_role`)
  take `(account, resource)` with no scope param; they already expose
  `summary`/`index_summary`.
- `Attendance` has **no coordinate columns** (allowed: `account_id,
  event_id, course_id, checked_in_at`). `AttendancePolicy#can_record?`
  already checks `event.live_now?`. Location coords are already encrypted.
- `GET /accounts/[username]` returns the account envelope + `policies` +
  `capabilities` (self only); it does **not** return an auth token yet.

### Threat model delta vs the previous branch

| Risk | Addressed here | Deferred |
| --- | --- | --- |
| A shared/leaked token grants full account power | Scope limits a token to read-only even when the account can write | Per-resource 3rd-party grants beyond full/read-only |
| Student spoofs presence | Haversine proximity (~55 m) to the event location | Anti-GPS-spoofing / attestation |
| Student location is PII in a DB dump | Encrypted coordinate columns | — |
| Account-detail "API key" over-powered if copied | Endpoint mints a read-only token, not the session token | Revocation / rotation |

### Domain scope (this branch only)

- New: `AuthScope` lib, `AuthorizedAccount` model, `AuthorizeAccount`
  service, an attendance-eligibility object, encrypted attendance
  coordinates.
- Changed: auth token (scope), all policies (scope param), attendance
  service + routes.

## Questions

- [x] **Q1. (Resolved 2026-05-27.)** `AuthorizedAccount` envelope is
  `{ type: 'authorized_account', attributes: { account: <account envelope>,
  auth_token: <token> } }` — **locked**; the account endpoint mints a
  read-only token in this envelope and the App consumes `data.attributes`.
- [x] **Q2. (Resolved 2026-05-27.)** Login mints full scope; only the
  account-detail endpoint mints read-only. No other token-minting sites.
- [x] **Q3. (Resolved 2026-05-27.)** Geofence: Haversine distance, radius
  from config `ATTENDANCE_RADIUS_M` (default ~55 m), not hard-coded.
- [x] **Q4. (Resolved 2026-05-28.)** Check-in body carries `{longitude,
  latitude}` (TLS in transit, encrypted at rest). New `OutOfRangeError →
  422` (matches existing `NotLiveError`); missing/invalid coords → 400.
  Haversine place check in `AttendanceEligibility`; temporal `live_now?`
  stays in `AttendancePolicy`. Kept: `NotAuthorized → 403`, `UnknownEvent
  → 404`, duplicate → 409.

## Scope

**In scope**: AuthScope lib; token scope; AuthorizedAccount +
AuthorizeAccount; scope checks in all policies; read-only account-detail
token; attendance coordinate encryption; eligibility (time + place);
teaching-staff attendance management routes; tests.

**Out of scope** (deferred per project rules):

- SSO / OIDC (the chained follow-on branch).
- Per-resource 3rd-party scope grants beyond full/read-only.
- App-side display of the read-only key.

## Tasks

> Check off as each finishes — do not batch.

### Lib
- [ ] 1. `app/lib/auth_scope.rb` — `ALL/READ/WRITE/EVERYTHING='*:write'/READ_ONLY='*:read'`; `can_read?`/`can_write?`.
- [ ] 2. `app/lib/auth_token.rb` — tokenize + read `scope`; `AuthToken.new(payload, scope:, expiration:)`; `#scope`; `load` sets `@scope`; default full scope for existing callers.

### Models / services
- [ ] 3. `app/models/authorized_account.rb` (Q1).
- [ ] 4. `app/services/authorize_account.rb` — `call(auth:, username:, auth_scope:)`; AccountPolicy gate.
- [ ] 5. `app/services/authenticate_account.rb` — mint full-scope token.

### Controllers
- [ ] 6. `app/controllers/app.rb` — `@auth = http_request.authorized_account`; keep `@auth_account` hash-compatible.
- [ ] 7. `app/controllers/http_request.rb` — `authorized_account` → `AuthorizedAccount`.
- [ ] 8. `app/controllers/accounts.rb` — account GET returns a read-only-scoped AuthorizedAccount.
- [ ] 9. `courses` / `events` / `locations` / `attendances` controllers — pass `auth_scope: @auth.scope` into services / inline policy calls.

### Policies (add `auth_scope` + can_read?/can_write?)
- [ ] 10. `course_policy.rb`
- [ ] 11. `event_policy.rb`
- [ ] 12. `location_policy.rb`
- [ ] 13. `attendance_policy.rb`
- [ ] 14. `account_policy.rb`
- [ ] 15. `enrollment_policy.rb`

### Geo-attendance
- [ ] 16. Additive `alter_table` migration: `longitude_secure`, `latitude_secure` on `attendances`.
- [ ] 17. `Attendance` model — encrypted coord setters/getters.
- [ ] 18. Attendance-eligibility object — `event.live_now?` + Haversine (~55 m).
- [ ] 19. `app/services/record_attendance.rb` — accept coords, run eligibility, store encrypted.
- [ ] 20. Routes: `POST .../attendances` takes coords; `GET .../courses/[id]/attendances/[event_id]` (staff list); `PUT .../courses/[id]/attendances/[event_id]/[account_id]` (staff toggle).

### Ops
- [ ] 21. Seed update if needed.
- [ ] 22. `Rakefile` parity check.

### Tests
- [ ] 23. `spec/unit/auth_scope_spec.rb`
- [ ] 24. Policy specs gate on scope (read-only denies writes).
- [ ] 25. Eligibility/geo specs (in-range allow, out-of-range deny, coord encryption round-trip).
- [ ] 26. Account-detail returns a read-only token spec.

### Verify
- [ ] 27. `rake spec`
- [ ] 28. `bundle exec rubocop .`
- [ ] 29. `bundle audit check --update`
- [ ] 30. Code review
- [ ] 31. Retrospective migration audit (diff + full-tree + shared-file content)
- [ ] 32. Squash to required commit count
- [ ] 33. Merge PR to `main` — deferred to user

## Commit strategy

- **Required payload count**: **1** (matches the reference branch).
- **Subject (verbatim from reference)**: `Provides auth-scoped access to resources`.
- Body notes the geo-attendance extension + encrypted coordinates.
- Plan commit (`docs: plan 8-auth-scope`) is scaffolding, not counted.

## Completed

(to be filled in during implementation)

## Post-Implementation Notes (for reviewer)

(to be filled in before review)

---

Last updated: 2026-05-27
