# Auth Migration: Clerk to phx.gen.auth + OAuth

**Date:** 2026-03-11
**Status:** Planned
**Owner:** product-manager

## Executive Summary

Replace Clerk (external auth SaaS) with Phoenix's built-in `phx.gen.auth` for session-based authentication, plus `ueberauth` for GitHub and Google OAuth login. This eliminates the Clerk CDN script, JWKS JWT verification, ETS caching, and the JOSE dependency. The device auth flow (CLI login via ed25519) is unchanged.

No backwards compatibility is needed -- the database can be reset.

## What's Changing

| Area | Current (Clerk) | Target (phx.gen.auth + OAuth) |
|------|----------------|-------------------------------|
| Web sign-in | Clerk JS CDN redirects to hosted login | Server-rendered login page + OAuth buttons (GitHub, Google) |
| Session management | Clerk `__session` cookie, server-side JWT re-verification every 15 min | Phoenix session token in `users_tokens` table, `remember_me` cookie |
| API auth (account endpoints) | `Authorization: Bearer <clerk-jwt>`, verified via JWKS/RS256 | Phoenix session token (browser) or Bearer token from `users_tokens` |
| User identity | `clerk_user_id` (external Clerk ID) | `user.id` (local UUID, our DB is source of truth) |
| Schema | `accounts` table with `clerk_user_id` column | `users` table with `email`, `hashed_password`, OAuth fields |
| Machine tokens | `account_tokens` table linking tokens to `account_id` | `machine_tokens` table linking tokens to `user_id` |
| Team ownership | `owner_account_id` on `teams` table | `owner_user_id` on `teams` table |
| Dependencies | `jose ~> 1.11`, Clerk CDN script, ETS JWKS cache | `ueberauth`, `ueberauth_github`, `ueberauth_google`, `bcrypt_elixir` |

## What's NOT Changing

- **Device auth flow**: The GenServer-based device authorization (CLI `teamrc login`, user code, polling) stays as-is. The only change is that the confirmation step uses `current_user` instead of `clerk_user_id`.
- **Ed25519 machine tokens**: The CLI's keypair-based auth (`trc_ak_` prefix, `VerifySignature` plug) is untouched.
- **API signature verification**: The `VerifySignature` plug for CLI API calls stays the same.
- **Team data model**: Teams, members, skills, invites, token_teams -- all unchanged except the `owner_account_id` column rename.

## User Impact

### Web users
- **Before:** Click "Sign in" -> redirect to Clerk hosted login -> redirect back with JWT cookie
- **After:** Click "Sign in" -> server-rendered page with "Continue with GitHub" / "Continue with Google" buttons -> OAuth flow -> redirect back with session cookie
- Email/password registration is also available via phx.gen.auth (optional, lower priority)

### CLI users
- No change to the CLI auth flow. `teamrc login` still opens browser, shows user code, polls for confirmation.
- The browser page they land on (`/auth/verify`) uses the new auth system instead of Clerk, but the UX is identical.

### Dashboard users
- Dashboard (`/dashboard`) works the same. `clerk_email` becomes `current_user.email`. Sign-out clears the Phoenix session instead of the Clerk session.

## Migration Phases

### Phase 0: Scaffold phx.gen.auth

**What:** Run `mix phx.gen.auth Accounts User users` to generate the baseline auth modules. Do NOT apply its migration yet -- we will write a consolidated one.

**Output:** Generated modules in `lib/teamrc/accounts/`, `lib/teamrc_web/controllers/user_session_controller.ex`, `lib/teamrc_web/user_auth.ex`, login/registration LiveViews.

**Assignee:** backend-dev
**Depends on:** Nothing
**Estimate:** 0.5 day

---

### Phase 1: Database reset + schema consolidation

**What:** Reset the database and write a single consolidated migration that:
- Creates `users` table (replacing `accounts`): `id` (binary_id), `email`, `hashed_password`, `confirmed_at`, plus OAuth fields (`provider`, `provider_uid`, `avatar_url`)
- Creates `users_tokens` table (phx.gen.auth standard, for session/email tokens)
- Creates `machine_tokens` table (replacing `account_tokens`): `user_id` FK, `token`, `machine_name`, `last_seen_at`, `revoked_at`
- Creates `teams` table with `owner_user_id` (replacing `owner_account_id`)
- All other tables (members, invites, token_teams) unchanged

**Schemas to update:**
- `Teamrc.Schema.Account` -> delete (replaced by generated `Teamrc.Accounts.User`)
- `Teamrc.Schema.AccountToken` -> `Teamrc.Accounts.MachineToken` (new schema, `account_id` -> `user_id`)
- `Teamrc.Schema.Team` -> `owner_account_id` field -> `owner_user_id`

**Assignee:** backend-dev
**Depends on:** Phase 0
**Estimate:** 1 day

---

### Phase 2: Accounts context merge

**What:** Merge the existing `Teamrc.Accounts` functions into the phx.gen.auth-generated `Teamrc.Accounts` module. The generated module provides `register_user/1`, `get_user_by_email/1`, `get_user_by_email_and_password/2`, session token CRUD, etc. We add:

- `link_token/3` (machine token linking)
- `get_user_with_machine_tokens/1` (was `get_account_with_tokens/1`)
- `get_user_teams/1` (was `get_account_teams/1`)
- `get_user_teams_with_machines/1` (was `get_account_teams_with_machines/1`)
- `is_team_participant?/2` (change first arg from `clerk_user_id` to `user_id`)
- `resolve_participants_batch/1`
- `revoke_token/2`
- `delete_user/1` (was `delete_account/1`)
- `export_user_data/1` (was `export_account_data/1`)
- `is_team_owner?/2`
- `reassociate_teams/2`
- `find_or_create_oauth_user/3` (new -- for ueberauth callback)

All functions change from taking `clerk_user_id` to taking `user_id` (the local DB primary key).

**Assignee:** backend-dev
**Depends on:** Phase 1
**Estimate:** 1 day

---

### Phase 3: Add ueberauth for GitHub + Google OAuth

**What:** Add ueberauth dependencies and configure OAuth:

1. Add to `mix.exs`: `ueberauth`, `ueberauth_github`, `ueberauth_google`
2. Configure in `config/`: strategy configs with env var client IDs/secrets
3. Create `TeamrcWeb.OAuthController` with `request/2` and `callback/2` actions
4. Add routes: `GET /auth/:provider` and `GET /auth/:provider/callback`
5. In callback: call `Accounts.find_or_create_oauth_user/3` to upsert user, then create session

The OAuth controller creates a Phoenix session (same as phx.gen.auth login) so the user gets a `_teamrc_web_user_remember_me` cookie.

**Assignee:** backend-dev
**Depends on:** Phase 2
**Estimate:** 1 day

---

### Phase 4: Router + plugs + hooks

**What:** Replace Clerk auth infrastructure in the request pipeline.

**Delete:**
- `TeamrcWeb.Plugs.VerifyClerkJWT` (192 lines)
- `TeamrcWeb.Plugs.SessionClerkAuth` (92 lines)

**Replace:**
- `TeamrcWeb.Hooks.AssignAuth` -> use phx.gen.auth's `on_mount` hooks (`UserAuth.on_mount(:mount_current_user, ...)` and `UserAuth.on_mount(:ensure_authenticated, ...)`)
- Router pipeline `:browser` -> remove `SessionClerkAuth` plug, add `UserAuth.fetch_current_user`
- Router pipeline `:clerk_api` -> replace with session-based or Bearer token auth
- Router pipeline `:clerk_and_signature_api` -> replace with session + signature
- `live_session :public` -> `on_mount: [{UserAuth, :mount_current_user}]`
- `live_session :authenticated` -> `on_mount: [{UserAuth, :ensure_authenticated}]`

**Update routes:**
- `GET /auth/sign-out` -> use phx.gen.auth's `DELETE /users/log_out` (or keep GET with CSRF-safe redirect)
- Add `/users/log_in`, `/users/register`, `/users/settings` (generated by phx.gen.auth)
- Add `/auth/github`, `/auth/github/callback`, `/auth/google`, `/auth/google/callback`

**Assignee:** backend-dev
**Depends on:** Phase 2, Phase 3
**Estimate:** 1 day

---

### Phase 5: Update LiveViews (6 files)

**What:** Replace all `clerk_user_id` / `clerk_email` references with `current_user`.

| LiveView | Changes |
|----------|---------|
| `AuthVerifyLive` | `clerk_user_id` -> `current_user.id`, `clerk_email` -> `current_user.email`. Step `:sign_in_required` redirects to `/users/log_in` instead of dispatching `trc:sign-in` JS event. |
| `DashboardLive` | `clerk_user_id` -> `current_user.id`, `clerk_email` -> `current_user.email`. `load_dashboard/1` uses `current_user.id` instead of looking up by `clerk_user_id`. |
| `TeamDetailLive` | `assigns[:clerk_user_id]` -> `assigns[:current_user]` for participant/owner checks. `@clerk_email` -> `@current_user.email` in template. |
| `TeamLive` | `resolve_owner_opts/2` takes `current_user` instead of `clerk_user_id` + `clerk_email`. |
| `MemberDetailLive` | `assigns[:clerk_user_id]` -> `assigns[:current_user]` for access check. |
| `LegalLive` | No auth references (confirmed grep found none). No changes needed. |

**Assignee:** frontend-dev
**Depends on:** Phase 4
**Estimate:** 1 day

---

### Phase 6: Update controllers

**What:** Update `AccountController` and `AuthController`.

**AccountController (5 actions):**
- All actions currently read `conn.assigns[:clerk_user_id]`. Replace with `conn.assigns[:current_user].id`.
- `delete/2` deletes user and logs out (clear session).

**AuthController (2 actions):**
- `poll_device/2` returns `clerk_user_id` and `email` in the confirmed response. Replace with `user_id` (or keep `email` only -- the CLI does not use `clerk_user_id`).
- `create_device/2` is unchanged (uses `verified_token` from signature auth).

**PageController:**
- `index/2`: `get_session(conn, "clerk_user_id")` -> check `conn.assigns[:current_user]`
- `sign_out/2`: replaced by phx.gen.auth's `UserSessionController.delete/2`

**Assignee:** backend-dev
**Depends on:** Phase 4
**Estimate:** 0.5 day

---

### Phase 7: Update device auth GenServer + frontend JS + layouts

**What:**

**DeviceAuth GenServer:**
- `Request` struct: `clerk_user_id` field -> `user_id`
- `confirm_request/4`: params change from `(user_code, clerk_user_id, email)` to `(user_code, user_id, email)`
- Poll response: return `user_id` instead of `clerk_user_id`

**Frontend JS (`app.js`):**
- Remove the entire `trc:sign-in` event handler (Clerk JS redirect logic, ~28 lines)
- Remove the `trc:sign-out` event handler (Clerk signOut call)
- Sign-in buttons now use standard `<a href="/users/log_in">` links instead of JS events

**Root layout (`root.html.heex`):**
- Remove the Clerk CDN `<script>` tag and its conditional

**App layout (`layouts.ex`):**
- Replace `clerk_email` / `clerk_user_id` attrs with `current_user`
- "Sign in" button -> `<a href="/users/log_in">` link
- "Sign out" -> `<a href="/users/log_out" method="delete">`
- User avatar/email display uses `@current_user.email`

**Assignee:** frontend-dev
**Depends on:** Phase 5
**Estimate:** 1 day

---

### Phase 8: Update teams context

**What:** Update `Teamrc.Teams` for the `owner_account_id` -> `owner_user_id` rename.

- `create_team_in_db_inner/3`: `owner_account_id` param and field -> `owner_user_id`
- `claim_ownership/2`: query `t.owner_account_id` -> `t.owner_user_id`, set `owner_user_id`
- `do_set_visibility/2` and `set_visibility/3`: pass through (uses `Accounts.is_team_owner?/2` which is already updated in Phase 2)

Also update `Teamrc.Accounts.is_team_owner?/2` to query `owner_user_id`.

**Assignee:** backend-dev
**Depends on:** Phase 2
**Estimate:** 0.5 day

---

### Phase 9: Remove all Clerk artifacts

**What:** Clean sweep to ensure zero Clerk references remain.

**Delete files:**
- `lib/teamrc_web/plugs/verify_clerk_jwt.ex`
- `lib/teamrc_web/plugs/session_clerk_auth.ex`
- `lib/teamrc_web/hooks/assign_auth.ex` (replaced by phx.gen.auth hooks)
- `lib/teamrc/schema/account.ex` (replaced by generated User schema)
- `lib/teamrc/schema/account_token.ex` (replaced by MachineToken)

**Delete test files:**
- `test/teamrc_web/plugs/verify_clerk_jwt_test.exs`
- `test/teamrc_web/plugs/session_clerk_auth_test.exs`
- `test/teamrc/schema/account_test.exs`

**Remove from `application.ex`:**
- `:inets.start()` and `:ssl.start()` (no longer needed for JWKS fetching)
- ETS table creation for `:clerk_jwks_cache`

**Remove from `config/`:**
- `runtime.exs`: `CLERK_PUBLISHABLE_KEY`, `CLERK_JWKS_URL`, `CLERK_ISSUER`, `CLERK_AUDIENCE` config blocks
- `test.exs`: `:skip_clerk_auth` config
- `validate_prod_config!/0`: remove Clerk warning

**Remove from `mix.exs`:**
- `{:jose, "~> 1.11"}`

**Assignee:** backend-dev
**Depends on:** All previous phases
**Estimate:** 0.5 day

---

### Phase 10: Update tests (8+ files)

**What:** Update all test files that reference Clerk.

| Test file | Changes |
|-----------|---------|
| `account_controller_test.exs` | Replace Clerk JWT setup with phx.gen.auth session login. Use `log_in_user/2` test helper. |
| `auth_controller_test.exs` | Update confirmed response assertions (`clerk_user_id` -> `user_id` or remove). |
| `device_auth_test.exs` | `clerk_user_id` -> `user_id` in `confirm_request` calls and assertions. |
| `page_controller_test.exs` | Update session checks for auth redirects. |
| `security_audit_test.exs` | Replace Clerk-specific auth bypass tests with phx.gen.auth equivalents. |
| `account_test.exs` | Delete (schema replaced) or rewrite for new User schema. |
| `verify_clerk_jwt_test.exs` | Delete entirely. |
| `session_clerk_auth_test.exs` | Delete entirely. |

Add new tests:
- OAuth controller tests (GitHub/Google callback, user creation, session establishment)
- User registration/login tests (generated by phx.gen.auth, customize)

**Assignee:** qa-engineer
**Depends on:** Phase 9
**Estimate:** 1.5 days

---

### Phase 11: PII isolation layer

**What:** Create a clear boundary between PII-bearing and PII-free code paths.

1. Create `Teamrc.PII` context module — all PII reads go through here with access control checks
2. Add `sanitized_participant/2` function that returns different fields based on requester relationship (owner/participant/viewer)
3. Audit all API controller responses — ensure team/sync endpoints never leak emails or user details
4. Add `user_profiles` table (display_name, avatar_url) separate from auth-sensitive `users` table
5. Add integration tests: "user A cannot see user B's email via any endpoint"
6. Add `X-PII-Access: true` response header on PII-bearing endpoints for monitoring

**Assignee:** backend-dev (security review by security-reviewer)
**Depends on:** Phase 2
**Estimate:** 1.5 days

---

### UX Design: Login/Registration Page

**What:** Design the server-rendered login page that replaces Clerk's hosted UI.

- OAuth-first layout: large "Continue with GitHub" and "Continue with Google" buttons
- Email/password as secondary option (expandable section or below fold)
- Consistent with teamrc's design system: zinc palette, indigo primary, monospace for identifiers
- Error states, loading states, redirect-back behavior
- Mobile responsive

**Assignee:** ux-designer
**Depends on:** Nothing (can start immediately, designs needed before Phase 5)
**Estimate:** 1 day

## Dependencies + Parallel Workstreams

```
Phase 0 (scaffold)
  |
  v
Phase 1 (DB reset)
  |
  v
Phase 2 (accounts merge) ----+---- Phase 8 (teams context)
  |                           |
  v                           |
Phase 3 (ueberauth)           |
  |                           |
  v                           |
Phase 4 (router/plugs) ------+
  |
  +------> Phase 5 (LiveViews) ----> Phase 7 (JS/layouts)
  |
  +------> Phase 6 (controllers)
  |
  v
Phase 9 (cleanup) -- depends on all above
  |
  v
Phase 10 (tests) -- depends on Phase 9

UX Design -- parallel with Phases 0-3, deliverable needed before Phase 5
```

**Phases 0-4** are sequential and backend-only (backend-dev).
**Phases 5 and 7** are frontend-dev work, parallelizable with Phase 6.
**Phase 8** can happen any time after Phase 2 (parallelizable with Phases 3-7).
**Phase 10** is a separate workstream for qa-engineer after code changes are complete.
**UX design** starts immediately and delivers before Phase 5.

## Team Assignment Summary

| Person | Phases | Days |
|--------|--------|------|
| backend-dev | 0, 1, 2, 3, 4, 6, 8, 9, 11 | ~7.5 days |
| frontend-dev | 5, 7, settings UI | ~3 days |
| ux-designer | Login page, settings pages, ToS flow design | ~1.5 days |
| qa-engineer | 10, PII leak tests | ~2 days |
| security-reviewer | Phase 11 review, red team | ~1 day |
| **Total calendar time** | | **~6 days** (with parallelism) |

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| OAuth provider configuration errors | Medium | Medium | Test with real GitHub/Google apps in dev. Document env vars clearly. |
| Session token security regression | Low | High | phx.gen.auth is battle-tested. Review generated code, do not customize token generation. |
| Missed Clerk reference causing runtime crash | Low | Medium | Final grep sweep in Phase 9. Add CI check: `grep -r "clerk" --include="*.ex" --include="*.exs" --include="*.heex" --include="*.js"` must return 0 results. |
| Device auth flow broken by user_id change | Medium | High | The GenServer stores ephemeral state, so the rename is straightforward. Test the full flow end-to-end: `teamrc login` -> browser confirm -> CLI poll success. |
| phx.gen.auth generator conflicts with existing code | Low | Low | Run generator into clean branch, cherry-pick needed files. We control the namespace. |

| PII leakage via BOLA/IDOR on API endpoints | Medium | Critical | See Phase 11 (PII isolation). Separate PII-bearing endpoints from team/sync endpoints. Never return user emails or PII in team API responses. |
| Missing ToS acceptance blocking legal compliance | Low | High | Enforce `accepted_terms_at` on registration. Block access until accepted. |

## Critical Security Requirements

### PII Isolation (Phase 11)

With Clerk, PII (emails, names) lived in Clerk's infrastructure and was never in our API responses unless explicitly requested. Moving auth in-house means **we now hold PII directly**. This requires deliberate separation:

**Principle: Team/sync API endpoints must NEVER return PII.**

The current `api_controller.ex` endpoints (team CRUD, sync, push/pull) use machine tokens and return team data. These must remain PII-free. PII (email, name, avatar) should only be accessible through:

1. **Authenticated account endpoints** (`/api/account/*`) — only return the requesting user's own PII
2. **LiveView assigns** — `@current_user` is only available in the user's own session, never broadcast
3. **Participant resolution** — when showing team participants in the dashboard, return only:
   - `email_hash` (SHA256 for Gravatar, not reversible to email)
   - `display_name` (user-chosen, not email)
   - `machine_count` (integer, no machine names)
   - Full email only visible to the user themselves or team owner (with explicit scope)

**Implementation:**
- Add a `PII` context module (`Teamrc.PII`) that wraps all PII access with audit logging
- API responses that include participant info use `sanitized_participant/2` which strips PII based on the requester's relationship to the data
- Add `X-PII-Access` response header on endpoints that return PII (for monitoring/alerting)
- Ecto schema: consider separating `user_profiles` table (display_name, avatar_url, bio) from `users` table (email, hashed_password) — different access patterns, different caching, different audit requirements

**BOLA/IDOR mitigations:**
- All account endpoints verify `conn.assigns.current_user.id == requested_user_id` (no `user_id` param — always from session)
- Machine token endpoints verify token belongs to `current_user` before returning details
- Team participant lists are scoped: owners see emails, participants see display names, viewers see nothing
- Add integration tests that verify: "user A cannot see user B's email through any endpoint"

### Terms of Service Acceptance (Phase 1 schema + Phase 5 UI)

**Schema change:** Add `accepted_terms_at` (`:utc_datetime`, nullable) to `users` table.

**Registration flow:**
- Checkbox: "I agree to the [Terms of Service](/legal/terms) and [Privacy Policy](/legal/privacy)" — required, not pre-checked
- On submit: set `accepted_terms_at` to `DateTime.utc_now()`
- OAuth flow: after first OAuth login, redirect to a "Complete registration" page with ToS checkbox before creating session
- If `accepted_terms_at` is nil, block access to all authenticated pages (redirect to ToS acceptance page)

**Terms update flow:**
- When ToS changes, add a `terms_version` field or a `latest_terms_date` config
- If `accepted_terms_at < latest_terms_date`, prompt re-acceptance on next login
- Store `terms_version_accepted` alongside `accepted_terms_at` for audit trail

### User Settings Pages (Phase 5 UI + phx.gen.auth)

phx.gen.auth generates basic settings. Extend with:

**Account Settings (`/settings`):**
- Change email (with re-confirmation)
- Change password (requires current password)
- Connected OAuth accounts (link/unlink GitHub, Google)
- Display name (used in team participant lists instead of email)

**Security Settings (`/settings/security`):**
- Active sessions (list, revoke)
- Machine tokens (list, revoke — moved from dashboard)
- Two-factor authentication (future, placeholder)

**Data & Privacy (`/settings/privacy`):**
- Export my data (JSON download)
- Delete my account (with confirmation)
- Terms of Service acceptance history

## Success Criteria

1. All existing tests pass (after updates in Phase 10)
2. `grep -ri "clerk" teamrc/lib/ teamrc/test/ teamrc/config/ teamrc/assets/` returns zero results
3. JOSE dependency removed from `mix.lock`
4. OAuth login works end-to-end: click "Continue with GitHub" -> authorize -> ToS acceptance -> redirected to dashboard with session
5. Device auth flow works end-to-end: `teamrc login` -> browser confirm (with phx.gen.auth session) -> CLI gets confirmed status
6. Dashboard shows user email, machines, teams (identical functionality to Clerk-based version)
7. No Clerk CDN script loaded in any page
8. CSP header updated (remove any Clerk-related domains if present)
9. New tests cover OAuth callback, user creation, session management
10. ToS checkbox is required on registration and first OAuth login — `accepted_terms_at` is set
11. No team/sync API endpoint returns PII (emails, names) — verified by integration tests
12. User settings pages work: change email, change password, connected accounts, export data, delete account
13. PII isolation: participant lists show `display_name` / `email_hash`, not raw emails (except to owner/self)

## Environment Variables

### Remove
- `CLERK_PUBLISHABLE_KEY`
- `CLERK_JWKS_URL`
- `CLERK_ISSUER`
- `CLERK_AUDIENCE`

### Add
- `GITHUB_CLIENT_ID`
- `GITHUB_CLIENT_SECRET`
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`

### Unchanged
- `SECRET_KEY_BASE`
- `SESSION_SIGNING_SALT`
- `SESSION_ENCRYPTION_SALT`
- `LIVE_VIEW_SIGNING_SALT`
- `DATABASE_URL`
