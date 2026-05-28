# 8-sso — Google SSO via OpenID Connect (id_token verification)

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update this plan before and after task and subtask implementations.

## Branch

`8-sso` — branched off the `8-auth-scope` tip (`b1ef591`), **not** `main`. It
carries the AuthScope work, so SSO accounts are minted with `FULL` scope. The
App's SSO branch builds against this branch's `/auth/sso` endpoint.

## Goal

Let users sign in with their Google account using **OpenID Connect**. The App
performs the OAuth code→token exchange with Google and hands the resulting
**`id_token`** (a Google-signed JWT) to this API. The API **verifies the
id_token cryptographically** against Google's JWKS — RS256 signature, plus
`iss` / `aud` (= our client id) / `exp` checks — then reads identity claims
(`sub`, `email`, `email_verified`, `name`, `picture`) straight from the verified
token. No userinfo network hop. Returns an encrypted auth token with `FULL`
scope.

## Why OIDC (not an access-token + userinfo callback)

The token handed to the API is a *verifiable signed identity assertion*, so the
API establishes identity by **signature verification** (trust the crypto)
rather than a userinfo callback (trust the network). 0 extra hops, audience
binding via `aud`, replay resistance via `exp`. Teaching point: the provider
dictates the algorithm (RS256) — RbNaCl can't do RSA, so we use the
OpenSSL-backed `jwt` gem for the primitive while validating the *claims*
ourselves.

## Strategy: Vertical Slice

1. Generic `OidcVerifier(jwks_uri, audience, allowed_issuers)` — fetch JWKS,
   cache by `kid`, RS256 verify, validate `iss`/`aud`/`exp`. `GoogleIdToken` is
   a thin configured instance. The verifier does **not** reject unverified
   email — that flag gates the link step, not the signature.
2. `GoogleAccount` mapper — claims → `{provider, external_id, email,
   email_verified, name, avatar}`.
3. `sso_identities` migration + `SsoIdentity` model, unique `(provider,
   external_id)` and `(account_id, provider)`.
4. `FindOrCreateSsoAccount` (provider-agnostic) — find by `(provider,
   external_id)` → verified-email link → create `member`.
5. `AuthenticateSso` — verify → map → find-or-create → `AuthorizedAccount`
   (`FULL` scope).
6. Route `POST /api/v1/auth/sso` body `{ id_token }`.
7. Tests with a self-signed RSA key + WebMock'd JWKS (no real Google creds).

## Current State

- [x] Plan created
- [x] Branch `8-sso` created off `8-auth-scope` (`b1ef591`)
- [x] `jwt` gem added (`~>3.1`, resolves 3.2.0)
- [x] `OidcVerifier` (generic) + `GoogleIdToken` (configured) + spec
- [x] `GoogleAccount` mapper (surfaces `sub` + `email_verified`)
- [x] `sso_identities` migration (`010`) + `SsoIdentity` model
- [x] `FindOrCreateSsoAccount` (provider-agnostic) service
- [x] `AuthenticateSso` service
- [x] `POST /auth/sso` route
- [x] `avatar` added to account `to_json` envelope (Option A)
- [x] Secrets example (`GOOGLE_CLIENT_ID`, all 3 envs) + secrets.yml
- [x] Tests green (245 runs / 537 assertions / 0 fail) / rubocop (102) / audit clean
- [ ] Live smoke test (needs real Google client id — see WALKTHROUGH)
- [ ] Code review
- [ ] Retrospective migration audit
- [ ] Squash to 1 payload commit
- [ ] Merge PR to `main` — deferred to user

## Key decisions / divergences from the reference branch

- **OIDC re-architecture.** The reference branch verified GitHub identity via an
  access-token + `GET /user` callback. This branch verifies a signed `id_token`
  against JWKS. New file with no counterpart: `app/lib/oidc_verifier.rb` +
  `app/lib/google_id_token.rb`.
- **Identity keyed on `(provider, external_id)`**, not email — new
  `sso_identities` table + `SsoIdentity` model + provider-agnostic
  `FindOrCreateSsoAccount` (the reference matched accounts by email directly).
- **Unverified-email guard.** A valid signature always authenticates (identity =
  `sub`). `email_verified` gates only the email *link* step: verified → may link
  to an existing account by email; unverified → never link. If an unverified
  email collides with an existing account we can neither link (takeover guard)
  nor create a duplicate (`email_hash` is unique), so `FindOrCreateSsoAccount`
  raises `EmailConflictError` → route returns **409**.
- **`jwt` gem (OpenSSL/RSA), not RbNaCl** — the provider signs with RS256.
- **`avatar` serialized** in the account `to_json` (Option A) so the App can show
  the Google photo. The reference never serialized avatar.

## Status → HTTP mapping (route)

- verification failure (bad sig / `aud` / `iss` / `exp` / malformed) → **401**
- missing `id_token` in body → **400**
- unverified-email collision (`EmailConflictError`) → **409**

## Tests

- `spec/unit/oidc_verifier_spec.rb` — happy + bad-sig / wrong-aud / wrong-iss /
  expired / unknown-kid / blank; plus `GoogleIdToken` configured instance.
- `spec/integration/service_find_or_create_sso_account_spec.rb` — new member,
  idempotent repeat, verified-email link, unverified-collision raises,
  unverified-no-collision creates, username collision suffix.
- `spec/integration/api_auth_spec.rb` — SSO happy (200 + FULL token + avatar),
  repeat reuses account, malformed → 401, wrong aud → 401, missing → 400.
- `spec/spec_helper.rb` — `SsoTestKeys` (lazy RSA key, JWKS, signed-token minter).

## Commit strategy

- **Required payload count**: **1** (matches the reference branch).
- **Subject (verbatim, GitHub→Google)**: `Accepts Google SSO auth request`.
- Body: record the OIDC re-architecture + `jwt`/JWKS verification.
- Plan commit (`docs: plan 8-sso`) is scaffolding, not counted.

## Infrastructure setup (USER-OPERATED — Decision #12)

The API needs `GOOGLE_CLIENT_ID` (the OAuth Web-application client id) to check
the id_token `aud`. It never needs the client secret. See the user walkthrough:
`WALKTHROUGH.google-oauth-setup.md` in the baby_tyto planning repo. Tests need
no real credentials.

---

Last updated: 2026-05-28
