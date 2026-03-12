# Security Fix and Merge Plan

## 1. Worktree Inventory and Merge Order

**Worktrees on disk (6 of 7 described):**

| # | Worktree ID | Role | Key Files | Dependencies |
|---|-------------|------|-----------|-------------|
| 1 | agent-ab81cf52 | Backend Dev 1 | Core auth scaffold, accounts.ex, User schema, OAuth controller, router, user_auth.ex, migration, device_auth, teams.ex, session controller, UserLive.* stubs | None (foundation) |
| 2 | agent-a5312e43 | Email Delivery | Swoosh + Resend config, Mailer module, plain-text UserNotifier | Depends on #1 (UserNotifier module name) |
| 3 | agent-a851ffd2 | HTML Email Templates | HTML+text UserNotifier (supersedes Email Delivery's notifier) | Depends on #2 (Swoosh/Mailer) |
| 4 | agent-afeeebb0 | Backend Dev 2 | PII module, PII header plug, pii_leak_test | Depends on #1 (User schema) |
| 5 | agent-a732957f | Frontend Dev | LiveView updates, JS cleanup, dashboard, auth_verify, settings, terms | Depends on #1 (router, user_auth) |
| 6 | agent-a3250356 | UX Designer | Login, registration, forgot_password, reset_password, terms, settings page designs | Depends on #1 (router), conflicts with #5 |
| 7 | agent-a10c1899 | Legal | Updated privacy/terms content | Missing from disk -- defer |

**Merge order:**

```
Step 1: Backend Dev 1 (agent-ab81cf52) -- foundation layer
Step 2: Email Delivery (agent-a5312e43) -- Swoosh config, Mailer module
Step 3: HTML Email Templates (agent-a851ffd2) -- replaces step 2's UserNotifier
Step 4: Backend Dev 2 (agent-afeeebb0) -- PII module (with fixes)
Step 5: Frontend Dev (agent-a732957f) -- LiveView updates (with convention fixes)
Step 6: UX Designer (agent-a3250356) -- ONLY login, registration, forgot_password, reset_password
Step 7: Security fixes applied on top of merged result
```

## 2. Merge Step Details

### Step 1: Backend Dev 1 (agent-ab81cf52)

This is the foundation. Take ALL files from this worktree.

**New files to add:**
- `teamrc/lib/teamrc/accounts/user.ex`
- `teamrc/lib/teamrc/accounts/user_token.ex`
- `teamrc/lib/teamrc/accounts/user_profile.ex`
- `teamrc/lib/teamrc/accounts/machine_token.ex`
- `teamrc/lib/teamrc/accounts/scope.ex`
- `teamrc/lib/teamrc/accounts/user_notifier.ex` (stub, will be replaced in Step 3)
- `teamrc/lib/teamrc_web/controllers/oauth_controller.ex`
- `teamrc/lib/teamrc_web/controllers/user_session_controller.ex`
- `teamrc/lib/teamrc_web/user_auth.ex`
- `teamrc/lib/teamrc_web/live/user_live/login.ex`
- `teamrc/lib/teamrc_web/live/user_live/registration.ex`
- `teamrc/lib/teamrc_web/live/user_live/confirmation.ex`
- `teamrc/lib/teamrc_web/live/user_live/settings.ex`
- `teamrc/lib/teamrc_web/live/user_live/accept_terms.ex`
- `teamrc/priv/repo/migrations/20260311000001_create_all_tables.exs`
- `teamrc/test/support/data_case.ex`
- `teamrc/test/support/fixtures/`
- `teamrc/test/teamrc/accounts_test.exs`
- `teamrc/test/teamrc_web/controllers/user_session_controller_test.exs`
- `teamrc/test/teamrc_web/live/user_live/`
- `teamrc/test/teamrc_web/user_auth_test.exs`

**Modified files:**
- `teamrc/lib/teamrc/accounts.ex` -- complete replacement
- `teamrc/lib/teamrc/device_auth.ex` -- user_id rename
- `teamrc/lib/teamrc/device_auth/request.ex` -- user_id field
- `teamrc/lib/teamrc/schema/team.ex` -- owner_user_id
- `teamrc/lib/teamrc/teams.ex` -- owner_user_id
- `teamrc/lib/teamrc/application.ex` -- remove Clerk ETS/inets
- `teamrc/lib/teamrc_web/router.ex` -- complete replacement
- `teamrc/lib/teamrc_web/controllers/account_controller.ex` -- current_scope
- `teamrc/lib/teamrc_web/controllers/auth_controller.ex` -- user_id
- `teamrc/lib/teamrc_web/controllers/page_controller.ex` -- current_scope
- `teamrc/lib/teamrc_web/components/layouts/root.html.heex` -- remove Clerk CDN
- `teamrc/config/config.exs` -- ueberauth config
- `teamrc/config/runtime.exs` -- remove Clerk, add OAuth env vars
- `teamrc/config/test.exs` -- remove skip_clerk_auth
- `teamrc/mix.exs` -- add ueberauth/bcrypt, remove jose
- `teamrc/mix.lock`
- `teamrc/test/support/conn_case.ex`

**Deleted files:**
- `teamrc/lib/teamrc/schema/account.ex`
- `teamrc/lib/teamrc/schema/account_token.ex`
- `teamrc/lib/teamrc_web/hooks/assign_auth.ex`
- `teamrc/lib/teamrc_web/plugs/session_clerk_auth.ex`
- `teamrc/lib/teamrc_web/plugs/verify_clerk_jwt.ex`
- `teamrc/priv/repo/migrations/20260305000001_create_teams.exs`
- `teamrc/priv/repo/migrations/20260305000002_create_accounts.exs`
- `teamrc/test/teamrc/schema/account_test.exs`
- `teamrc/test/teamrc/schema/account_token_test.exs`
- `teamrc/test/teamrc_web/plugs/session_clerk_auth_test.exs`
- `teamrc/test/teamrc_web/plugs/verify_clerk_jwt_test.exs`

### Step 2: Email Delivery (agent-a5312e43)

**Take:**
- `teamrc/lib/teamrc/mailer.ex` -- Swoosh mailer module
- Config changes from `config.exs`, `dev.exs`, `runtime.exs`, `test.exs` -- Swoosh/Resend configuration
- `mix.exs` addition: `{:swoosh, "~> 1.5"}`
- `teamrc/lib/teamrc/application.ex` additions: Finch child_spec for Swoosh

**Do NOT take:**
- `teamrc/lib/teamrc/accounts/user_notifier.ex` -- will be superseded in Step 3

### Step 3: HTML Email Templates (agent-a851ffd2)

**Take:**
- `teamrc/lib/teamrc/accounts/user_notifier.ex` -- this is the final version with HTML+text dual format

**Needed additions** (missing from this worktree):
- Add `deliver_login_instructions/2` function to this UserNotifier. The Backend Dev 1's accounts.ex calls this for magic link flow. The HTML Email Templates version only has `deliver_confirmation_instructions`, `deliver_reset_password_instructions`, `deliver_update_email_instructions`, and `deliver_welcome`. The `deliver_login_instructions` must be added with both text and HTML bodies, following the same pattern.

### Step 4: Backend Dev 2 (agent-afeeebb0)

**Take:**
- `teamrc/lib/teamrc/pii.ex` -- with fix (see C4 below)
- `teamrc/lib/teamrc_web/plugs/pii_header.ex`
- `teamrc/test/teamrc/pii_test.exs`
- `teamrc/test/teamrc_web/controllers/pii_leak_test.exs`

**Do NOT take (already handled by Step 1):**
- Device auth rename changes (already in Backend Dev 1)
- Clerk cleanup changes to plugs (already deleted in Backend Dev 1)
- Config changes (already handled by Step 1)

### Step 5: Frontend Dev (agent-a732957f)

**Take:**
- `teamrc/assets/js/app.js` -- Clerk JS removal
- `teamrc/lib/teamrc_web/components/layouts.ex` -- updated layouts
- `teamrc/lib/teamrc_web/components/layouts/root.html.heex` -- merge with Step 1's version
- `teamrc/lib/teamrc_web/live/auth_verify_live.ex` -- with convention fixes
- `teamrc/lib/teamrc_web/live/dashboard_live.ex` -- with convention and security fixes
- `teamrc/lib/teamrc_web/live/legal_live.ex`
- `teamrc/lib/teamrc_web/live/member_detail_live.ex`
- `teamrc/lib/teamrc_web/live/team_detail_live.ex`
- `teamrc/lib/teamrc_web/live/team_live.ex`
- `teamrc/lib/teamrc_web/live/terms_live.ex` -- Frontend Dev's version (NOT UX Designer's)
- `teamrc/lib/teamrc_web/live/settings_live.ex` -- Frontend Dev's version (NOT UX Designer's)

**Convention fixes required during merge** (every `@current_user` reference must become `@current_scope.user`):
- All of the above LiveView files use `socket.assigns.current_user` and `@current_user` -- change to `socket.assigns.current_scope.user` and `@current_scope.user`

### Step 6: UX Designer (agent-a3250356) -- selective

**Take (these have no Frontend Dev equivalent):**
- `teamrc/lib/teamrc_web/live/user_login_live.ex` -- polished OAuth-first login page
- `teamrc/lib/teamrc_web/live/user_registration_live.ex` -- polished registration with ToS checkbox
- `teamrc/lib/teamrc_web/live/user_forgot_password_live.ex` -- password reset request
- `teamrc/lib/teamrc_web/live/user_reset_password_live.ex` -- password reset form

**Discard (Frontend Dev versions are better):**
- `teamrc/lib/teamrc_web/live/terms_live.ex` -- references `clerk_email`, `clerk_user_id`, redirects to `/auth/accept_terms`. Use Frontend Dev's version.
- `teamrc/lib/teamrc_web/live/user_settings_live.ex` -- references `clerk_email`, uses `connected_providers` assign that doesn't exist. Use Frontend Dev's `settings_live.ex`.

**Naming conflict resolution:**
- Backend Dev 1 generated `UserLive.Login` at `live/user_live/login.ex`, UX Designer created `UserLoginLive` at `live/user_login_live.ex`
- **Decision:** Use the UX Designer's polished designs but adapt them to the `UserLive.*` namespace convention from Backend Dev 1. Move them to:
  - `live/user_live/login.ex` as `TeamrcWeb.UserLive.Login` (replace stub)
  - `live/user_live/registration.ex` as `TeamrcWeb.UserLive.Registration` (replace stub)
  - `live/user_live/forgot_password.ex` as `TeamrcWeb.UserLive.ForgotPassword` (new)
  - `live/user_live/reset_password.ex` as `TeamrcWeb.UserLive.ResetPassword` (new)

**Router integration for forgot/reset password:** Add these routes to the router in the `:current_user` live_session:
```elixir
live "/users/forgot-password", UserLive.ForgotPassword, :new
live "/users/reset-password/:token", UserLive.ResetPassword, :new
```

## 3. Security Fixes

### CRITICAL

**C1: OAuth account takeover via email match**
- **File:** `/teamrc/lib/teamrc/accounts.ex`, `find_or_create_oauth_user/3` (lines 70-98)
- **Current behavior:** If email exists with a different provider, silently updates the existing user's OAuth fields (lines 88-97). This means an attacker who controls an OAuth account with the same email can take over the existing account.
- **Fix:** Change the `%User{} = user` branch:
  ```elixir
  %User{} = user ->
    cond do
      # Same provider, same UID -- returning user
      user.provider == provider && user.provider_uid == uid ->
        {:ok, user}

      # Same provider, different UID -- suspicious, reject
      user.provider == provider ->
        {:error, :email_already_registered}

      # Different provider -- do NOT auto-link. Return error.
      # Linking must happen from authenticated settings page.
      not is_nil(user.provider) ->
        {:error, :email_registered_with_different_provider}

      # No provider set (email/password user) -- do NOT auto-link
      is_nil(user.provider) ->
        {:error, :email_already_registered}
    end
  ```
- **Additionally:** Add `link_oauth_provider/3` function for authenticated users to link from settings:
  ```elixir
  def link_oauth_provider(%User{} = user, provider, uid) do
    user
    |> Ecto.Changeset.change(%{provider: provider, provider_uid: uid})
    |> Repo.update()
  end
  ```
- **OAuth controller update:** In `oauth_controller.ex`, handle the new error atoms and flash an appropriate message like "An account with this email already exists. Please log in with your password and link this provider in Settings."

**C2: accept_terms type mismatch**
- **File:** `/teamrc/lib/teamrc_web/live/terms_live.ex` (Frontend Dev, line 31)
- **Current:** `Accounts.accept_terms(current_user.id, @current_terms_version)` -- passes string ID
- **Fix:** `Accounts.accept_terms(current_user, @current_terms_version)` -- pass full struct
- **Also:** After convention fix, this becomes `socket.assigns.current_scope.user`

**C3: No server-side ToS enforcement**
- **File 1:** `/teamrc/lib/teamrc_web/user_auth.ex`, `require_authenticated_user/2` plug (lines 270-280)
- **Fix:** After the `if conn.assigns.current_scope && conn.assigns.current_scope.user` check succeeds, add:
  ```elixir
  if is_nil(conn.assigns.current_scope.user.accepted_terms_at) do
    conn
    |> put_session(:user_return_to, current_path(conn))
    |> redirect(to: ~p"/users/accept-terms")
    |> halt()
  else
    conn
  end
  ```
- **File 2:** `/teamrc/lib/teamrc_web/user_auth.ex`, `on_mount(:require_authenticated, ...)` (lines 218-231)
- **Fix:** After confirming `current_scope.user` exists, add ToS check:
  ```elixir
  if is_nil(socket.assigns.current_scope.user.accepted_terms_at) do
    socket = Phoenix.LiveView.redirect(socket, to: ~p"/users/accept-terms")
    {:halt, socket}
  else
    {:cont, socket}
  end
  ```
- **File 3:** `UserLive.Registration` -- add server-side `accepted_terms_at` when `terms_accepted == "true"`. The `register_user/1` changeset should set `accepted_terms_at: DateTime.utc_now(:second)` when the terms checkbox is checked.
- **File 4:** `UserSessionController.create/3` -- after email+password login, check `user.accepted_terms_at`. If nil, redirect to accept-terms instead of logging in.

**C4: PII module references deleted schema**
- **File:** `/teamrc/lib/teamrc/pii.ex`, `get_user_pii/2` (line 79)
- **Current:** `Teamrc.Repo.get(Teamrc.Schema.Account, user_id)` -- `Teamrc.Schema.Account` is deleted
- **Fix:** Change to `Teamrc.Repo.get(Teamrc.Accounts.User, user_id)` and update the map keys to match User fields:
  ```elixir
  def get_user_pii(user_id, requesting_user_id) when user_id == requesting_user_id do
    case Teamrc.Repo.get(Teamrc.Accounts.User, user_id) do
      nil -> nil
      user ->
        %{
          "id" => user.id,
          "email" => user.email,
          "created_at" => user.inserted_at,
          "updated_at" => user.updated_at
        }
    end
  end
  ```

### HIGH

**H1: PII leak in dashboard + API**
- **File 1:** `/teamrc/lib/teamrc_web/live/dashboard_live.ex` (Frontend Dev)
  - `resolve_participants_batch` returns raw emails at line 22. These are displayed at line 315 via `participant_display/2`.
  - **Fix:** In `load_dashboard/1`, replace raw participant emails with sanitized data:
    ```elixir
    # Determine access level per team
    sanitized_participants = Enum.into(participants, %{}, fn {team_id, emails} ->
      sanitized = Enum.map(emails, fn email ->
        access = if email == current_user.email, do: :self, else: :participant
        PII.sanitized_participant(%{email: email}, access)
      end)
      {team_id, sanitized}
    end)
    ```
  - Update the template to display `p["display_name"]` instead of raw email.
- **File 2:** `/teamrc/lib/teamrc_web/controllers/account_controller.ex`, `teams/2` (line 59)
  - `participants: Map.get(participants_map, team.id, ["anonymous"])` returns raw emails in API response.
  - **Fix:** Pipe through PII sanitization with `:self` for the requesting user's email, `:participant` for others.
- **File 3:** Ensure `resolve_participants_batch/1` is never called directly from templates or API responses without sanitization. Consider making it `@doc false` or private, and providing a `resolve_sanitized_participants_batch/2` that takes the requesting user_id.

**H2: Account deletion type mismatch**
- **File:** `/teamrc/lib/teamrc_web/live/dashboard_live.ex` (Frontend Dev, line 127) AND `/teamrc/lib/teamrc_web/live/settings_live.ex` (Frontend Dev, line 133)
- **Current:** `Accounts.delete_user_and_data(socket.assigns.current_user.id)` -- passes string ID
- **Fix:** `Accounts.delete_user_and_data(socket.assigns.current_scope.user)` -- pass full struct
- The `delete_user_and_data/1` function signature expects `%User{}` struct (line 521 of accounts.ex).

**H3: revoke_machine_token ignores transaction result**
- **File:** `/teamrc/lib/teamrc/accounts.ex`, `revoke_machine_token/2` (lines 430-447)
- **Current:** Lines 436-446 always return `:ok` regardless of `Repo.transaction` result.
- **Fix:**
  ```elixir
  machine_token ->
    case Repo.transaction(fn ->
      machine_token
      |> MachineToken.changeset(%{revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)})
      |> Repo.update!()

      from(tt in TokenTeam, where: tt.token == ^token)
      |> Repo.delete_all()
    end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  ```

**H4: OAuth callback missing request/2 handler**
- **File:** `/teamrc/lib/teamrc_web/router.ex` (lines 61-66) and `/teamrc/lib/teamrc_web/controllers/oauth_controller.ex`
- **Current:** Route `get "/:provider", OAuthController, :request` accepts ANY provider string. Visiting `/auth/badprovider` will crash because Ueberauth has no strategy for it.
- **Fix option A (preferred):** Replace the wildcard route with explicit routes:
  ```elixir
  scope "/auth", TeamrcWeb do
    pipe_through :browser
    get "/github", OAuthController, :request
    get "/github/callback", OAuthController, :callback
    get "/google", OAuthController, :request
    get "/google/callback", OAuthController, :callback
  end
  ```
- **Fix option B:** Add a `request/2` fallback in OAuthController:
  ```elixir
  def request(conn, _params) do
    conn
    |> put_flash(:error, "Unsupported authentication provider.")
    |> redirect(to: ~p"/users/log-in")
  end
  ```
- Prefer option A because it eliminates the surface entirely.

**H5: Export data leaks co-participant emails**
- **File:** `/teamrc/lib/teamrc/accounts.ex`, `export_user_data/1` (line 581)
- **Current:** `participants: Map.get(participants, team.id, [])` includes raw emails of all participants.
- **Fix:** Sanitize using PII module:
  ```elixir
  participants: Map.get(participants, team.id, [])
  |> Enum.map(fn email ->
    access = if email == user.email, do: :self, else: :participant
    Teamrc.PII.sanitized_participant(%{email: email}, access)
  end)
  ```

**H6: remember_me cookie missing secure: true**
- **File:** `/teamrc/lib/teamrc_web/user_auth.ex` (lines 14-18)
- **Current:**
  ```elixir
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]
  ```
- **Fix:** Add `secure: true` and `http_only: true`:
  ```elixir
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax",
    secure: true,
    http_only: true
  ]
  ```

### MEDIUM

**M1: Password min mismatch 8 (UI) vs 12 (schema)**
- **File:** `/teamrc/lib/teamrc_web/live/user_registration_live.ex` (UX Designer, line 59)
- **Current:** `if String.length(params["password"] || "") < 8` and placeholder "At least 8 characters"
- **Fix:** Change `< 8` to `< 12`, change placeholder to "At least 12 characters"
- **Also in:** UX Designer's reset password page placeholder "At least 8 characters" -- change to 12

**M2: OAuth race condition on concurrent registration**
- **File:** `/teamrc/lib/teamrc/accounts.ex`, `find_or_create_oauth_user/3`
- **Current:** `Repo.get_by(User, email: email)` then `Repo.insert()` is not atomic -- two concurrent OAuth callbacks with the same email can both see nil and both try to insert.
- **Fix:** Wrap in transaction with `on_conflict`:
  ```elixir
  def find_or_create_oauth_user(provider, uid, info) do
    email = info[:email] || info["email"]
    avatar_url = info[:avatar_url] || info["avatar_url"]

    Repo.transaction(fn ->
      case Repo.get_by(User, email: email) do
        nil ->
          attrs = %{...}
          case %User{} |> User.oauth_changeset(attrs) |> Repo.insert() do
            {:ok, user} -> user
            {:error, changeset} ->
              # Unique constraint violation -- concurrent insert won
              if has_unique_error?(changeset, :email) do
                case Repo.get_by(User, email: email) do
                  %User{provider: ^provider, provider_uid: ^uid} = user -> user
                  _ -> Repo.rollback(:email_already_registered)
                end
              else
                Repo.rollback(:insert_failed)
              end
          end
        %User{provider: ^provider, provider_uid: ^uid} = user -> user
        %User{} -> Repo.rollback(:email_registered_with_different_provider)
      end
    end)
  end
  ```

**M3: provider_uid length unconstrained**
- **File 1:** `/teamrc/lib/teamrc/accounts/user.ex`, `oauth_changeset/2` (line 126)
- **Fix:** Add `|> validate_length(:provider_uid, max: 255)`
- **File 2:** `/teamrc/priv/repo/migrations/20260311000001_create_all_tables.exs` (line 21)
- **Current:** `add :provider_uid, :string` -- no size constraint
- **Fix:** `add :provider_uid, :string, size: 255`

**M4: ToS purely client-side for email/password registration**
- **File:** `UserSessionController` or the registration handler
- **Fix:** When registering a user with email/password via `register_user/1`, the caller must pass `accepted_terms_at` in the attrs if the ToS checkbox was checked. Add validation in `register_user/1`:
  ```elixir
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> validate_terms_accepted(attrs)
    |> Repo.insert()
  end

  defp validate_terms_accepted(changeset, %{terms_accepted: "true"} = _attrs) do
    Ecto.Changeset.put_change(changeset, :accepted_terms_at, DateTime.utc_now(:second))
    |> Ecto.Changeset.put_change(:terms_version_accepted, "2026-03-11")
  end

  defp validate_terms_accepted(changeset, _attrs) do
    Ecto.Changeset.add_error(changeset, :terms_accepted, "must be accepted")
  end
  ```

**M5: pending_oauth_user_id causes nil crash in AcceptTerms LiveView**
- **File:** `/teamrc/lib/teamrc_web/live/user_live/accept_terms.ex` (Backend Dev 1, line 51-63)
- **Current:** Reads `session["pending_oauth_user_id"]` -- if nil, `Accounts.get_user!` crashes
- **Fix:** Handle nil case in `mount`:
  ```elixir
  def mount(_params, session, socket) do
    pending_user_id = session["pending_oauth_user_id"]

    if is_nil(pending_user_id) do
      {:ok, redirect(socket, to: ~p"/users/log-in")}
    else
      case Accounts.get_user(pending_user_id) do
        nil -> {:ok, redirect(socket, to: ~p"/users/log-in")}
        user -> {:ok, assign(socket, pending_user: user)}
      end
    end
  end
  ```
  And in `handle_event("accept", ...)`:
  ```elixir
  user = socket.assigns.pending_user
  {:ok, _user} = Accounts.accept_terms(user, "2026-03-11")
  ```

## 4. Convention Alignment (current_user to current_scope)

Every Frontend Dev LiveView file uses `@current_user` and `socket.assigns.current_user` / `socket.assigns[:current_user]`. The Backend Dev 1's `user_auth.ex` assigns `current_scope` (a `Scope` struct with a `.user` field). These must all be updated.

**Files requiring current_user to current_scope.user conversion:**

| File | References to change |
|------|---------------------|
| `dashboard_live.ex` | `socket.assigns[:current_user]` -> `socket.assigns[:current_scope]`, `socket.assigns.current_user` -> `socket.assigns.current_scope.user`, `@current_user` -> `@current_scope.user` (5+ locations) |
| `terms_live.ex` | `socket.assigns.current_user` -> `socket.assigns.current_scope.user`, `@current_user` -> `@current_scope.user` (3 locations) |
| `settings_live.ex` | `socket.assigns.current_user` -> `socket.assigns.current_scope.user`, `@current_user` -> `@current_scope.user` (8+ locations) |
| `auth_verify_live.ex` | `socket.assigns[:current_user]` -> nil-check on `socket.assigns[:current_scope]&.user`, `@current_user` -> `@current_scope.user` (4 locations) |
| `dashboard_live.ex` mount | `is_nil(socket.assigns[:current_user])` -> `is_nil(socket.assigns[:current_scope]) or is_nil(socket.assigns.current_scope.user)` |

**Function call mismatches to fix:**
- `dashboard_live.ex` line 102: `Accounts.revoke_token` -> `Accounts.revoke_machine_token`
- `settings_live.ex` line 48: `Accounts.update_display_name` -> does not exist; must be added to accounts.ex
- `settings_live.ex` line 67: `Accounts.apply_user_email` -> does not exist; this is a changeset validation function. Either add it or use `change_user_email` + `Repo.update`.
- `settings_live.ex` line 93: `Accounts.update_user_password(current_user, params["current_password"], %{...})` -- the Backend Dev 1's function signature is `update_user_password(user, attrs)` with no separate current_password param. Must reconcile.

## 5. UX Designer Files: Keep vs Discard

| File | Decision | Reason |
|------|----------|--------|
| `user_login_live.ex` | **KEEP** (move to `user_live/login.ex`) | Polished OAuth-first login design, no security issues |
| `user_registration_live.ex` | **KEEP** (move to `user_live/registration.ex`) | Has ToS checkbox, OAuth-first, nice design. Fix password min to 12. |
| `user_forgot_password_live.ex` | **KEEP** (move to `user_live/forgot_password.ex`) | Clean design, no conflicts |
| `user_reset_password_live.ex` | **KEEP** (move to `user_live/reset_password.ex`) | Clean design. Fix placeholder to "12 characters". |
| `terms_live.ex` | **DISCARD** | References `clerk_email`, `clerk_user_id`, redirects to non-existent `/auth/accept_terms`. Use Frontend Dev's version. |
| `user_settings_live.ex` | **DISCARD** | References `clerk_email`, uses unimplemented assigns like `connected_providers`, `sessions`. Use Frontend Dev's `settings_live.ex`. |

## 6. Phoenix 1.8 Feature Integration

### Magic Links
- Already partially implemented in Backend Dev 1's `accounts.ex` (`deliver_login_instructions`, `get_user_by_magic_link_token`, `login_user_by_magic_link`)
- Already in router: `live "/users/log-in/:token", UserLive.Confirmation, :new`
- The UX Designer's Login page has email/password form. Add a "Send magic link" button/option alongside the email/password form, or make the email-only registration flow (no password) the primary email flow.
- **Integration point:** The `UserLive.Login` page should have a "Send me a link instead" option that calls `Accounts.deliver_login_instructions`.

### Sudo Mode
- Already scaffolded in `user_auth.ex` with `on_mount(:require_sudo_mode, ...)` (lines 233-246) and `Accounts.sudo_mode?/2` (lines 123-129).
- **Integration points for destructive operations:**
  - Delete account (in `settings_live.ex` / `dashboard_live.ex`) -- wrap route with `:require_sudo_mode` on_mount
  - Change password (`UserSessionController.update_password` already checks `Accounts.sudo_mode?`)
  - Revoke machine tokens -- add sudo mode check
  - Change email -- add sudo mode check
- **Router changes:** Add a separate `live_session :sudo` or add `:require_sudo_mode` as additional on_mount to the settings route:
  ```elixir
  live_session :require_sudo_mode,
    on_mount: [{TeamrcWeb.UserAuth, :require_authenticated}, {TeamrcWeb.UserAuth, :require_sudo_mode}] do
    live "/users/settings/security", UserLive.Settings, :security
  end
  ```

### Scope Convention
- Backend Dev 1 correctly uses `current_scope` everywhere. This is the Phoenix 1.8 pattern.
- The `Scope` struct at `/teamrc/lib/teamrc/accounts/scope.ex` wraps the user.
- All Frontend Dev files need updating (covered in section 4).

## 7. Missing Functions to Implement

The Frontend Dev's `settings_live.ex` calls functions that don't exist in Backend Dev 1's `accounts.ex`:

1. **`Accounts.update_display_name(user_id, display_name)`** -- needs implementation:
   ```elixir
   def update_display_name(user_id, display_name) do
     case Repo.get_by(UserProfile, user_id: user_id) do
       nil ->
         %UserProfile{}
         |> UserProfile.changeset(%{user_id: user_id, display_name: display_name})
         |> Repo.insert()
       profile ->
         profile
         |> UserProfile.changeset(%{display_name: display_name})
         |> Repo.update()
     end
   end
   ```

2. **`Accounts.apply_user_email(user, attrs)`** -- needed for settings email change validation without persisting:
   ```elixir
   def apply_user_email(user, attrs) do
     user
     |> User.email_changeset(attrs)
     |> Ecto.Changeset.apply_action(:update)
   end
   ```

3. **`deliver_login_instructions/2`** must be added to the HTML Email Templates UserNotifier (Step 3 gap).

## 8. Verification Checklist

After merge and all fixes applied:

- [ ] **Compile:** `mix compile --warnings-as-errors` succeeds with zero warnings
- [ ] **Database reset:** `mix ecto.reset` runs the consolidated migration cleanly
- [ ] **Tests pass:** `mix test` passes (update failing tests)
- [ ] **No Clerk references:** `grep -ri "clerk" teamrc/lib/ teamrc/test/ teamrc/config/ teamrc/assets/` returns zero results
- [ ] **C1 verified:** Test that OAuth login with an email already registered by another provider returns error, not account takeover
- [ ] **C2 verified:** `accept_terms` receives `%User{}` struct, not string ID
- [ ] **C3 verified:** Visit `/dashboard` without accepting ToS -> redirected to `/users/accept-terms`. Try `curl` to `/api/account` without ToS -> blocked.
- [ ] **C4 verified:** `PII.get_user_pii/2` references `Teamrc.Accounts.User`, not `Teamrc.Schema.Account`
- [ ] **H1 verified:** Dashboard participant list shows display names, not raw emails. API `/api/account/teams` returns sanitized participants.
- [ ] **H2 verified:** `delete_user_and_data` receives `%User{}` struct in all call sites
- [ ] **H3 verified:** `revoke_machine_token` returns `{:error, reason}` on transaction failure
- [ ] **H4 verified:** `GET /auth/badprovider` returns redirect with flash, not 500 error
- [ ] **H5 verified:** Export data JSON does not contain co-participant raw emails
- [ ] **H6 verified:** Remember-me cookie has `secure: true`, `http_only: true`
- [ ] **M1 verified:** Registration form and reset password form both show "12 characters" minimum
- [ ] **M3 verified:** OAuth changeset validates `provider_uid` max length 255
- [ ] **M4 verified:** Email/password registration sets `accepted_terms_at` server-side when checkbox is checked
- [ ] **M5 verified:** `/users/accept-terms` with no `pending_oauth_user_id` session redirects to login (no crash)
- [ ] **Convention verified:** Zero references to `@current_user` in any LiveView; all use `@current_scope.user`
- [ ] **Convention verified:** Zero references to `Accounts.revoke_token`; all use `Accounts.revoke_machine_token`
- [ ] **Magic links work:** Enter email -> receive link -> click link -> logged in
- [ ] **Sudo mode works:** Accessing settings/security requires recent authentication
- [ ] **OAuth flow works:** GitHub button -> authorize -> ToS page (if first time) -> dashboard
- [ ] **Device auth flow works:** `teamrc login` -> browser verify -> confirmed
- [ ] **Email delivery works:** Swoosh adapter sends via Resend in prod, local in dev, test adapter in test
- [ ] **PII header present:** `X-PII-Access: true` header appears on `/api/account` responses

## Critical Files for Implementation

- `/teamrc/lib/teamrc/accounts.ex` - Core business logic: fix C1 (OAuth takeover), H3 (revoke transaction), H5 (export PII), add missing functions (update_display_name, apply_user_email)
- `/teamrc/lib/teamrc_web/user_auth.ex` - Auth pipeline: fix C3 (ToS enforcement in plug and on_mount), H6 (cookie secure flag)
- `/teamrc/lib/teamrc_web/live/dashboard_live.ex` - Frontend hub: fix H1 (PII leak), H2 (delete type mismatch), convention alignment (current_user -> current_scope.user), function name fix (revoke_token -> revoke_machine_token)
- `/teamrc/lib/teamrc/pii.ex` - PII layer: fix C4 (Schema.Account -> Accounts.User reference)
- `/teamrc/lib/teamrc_web/controllers/oauth_controller.ex` - OAuth flow: update for C1 error handling (new error atoms from accounts.ex), fix H4 (route restriction or request/2 fallback)
