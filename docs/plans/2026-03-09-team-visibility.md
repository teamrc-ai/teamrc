# Team Visibility: Public/Private Teams, Clone vs Invite

**Date**: 2026-03-09
**Status**: Draft

## Problem

`/teams/:id` is a public page. Anyone with a team's UUID can view the full team config, machine hostnames, participant emails, and invite codes. The UUID leaks to anyone who receives an invite (even expired ones, since the invite page redirects to `/teams/:id?invite=...` which can be bookmarked).

There's also no concept of team ownership. `can_edit` is true for any signed-in user whose token is connected to the team. This is called `can_edit_owner` in the template but that name is misleading.

Additionally, the only sharing mechanism is invite codes, which create ongoing sync relationships. There's no way to share a team config as a one-time copy without joining the sync loop.

## Current State

### Data model
- `Team`: id (UUID), name, skills, platforms, knowledge
- `Member`: belongs_to Team, has name/role/soul/skills
- `Invite`: code (`trc_inv_...`), expires_at, belongs_to Team
- `TokenTeam`: join table (token, team_id, scope, project_name, last_seen_at)
- `AccountToken`: token, machine_name, last_seen_at, belongs_to Account
- No `visibility`, `slug`, or `created_by` field on Team

### Access control on `/teams/:id`
- Page loads for anyone with the UUID. No auth check.
- `can_edit` = signed in + has a token in the team's token_teams. Grants: edit team name, add/edit/remove members, add/edit/remove skills, generate invites.
- Visible to everyone: team name, members, skills, knowledge.
- Visible to `can_edit` users: invites, participants, (previously) machines.

### How people reach `/teams/:id`
1. **Team creator**: Redirected after creating team on `/new`. Gets `?invite=CODE` in URL.
2. **Invite URL**: `/invite/trc_inv_...` validates the code, redirects to `/teams/:id?invite=CODE`.
3. **Dashboard**: `/dashboard` links to `/teams/:id` for authenticated users.
4. **CLI users**: Team ID is in `.teamrc.yaml`, but they'd have to manually construct the URL.
5. **Direct link**: Anyone with the UUID.

### CLI clone command
`teamrc clone <invite-code>` already exists. It calls `preview_by_invite` (read-only, no token_team created), writes files locally, and tells the user to `teamrc join` if they want ongoing sync. But it requires an invite code, which expires.

## Design

### 1. Team visibility field

Add `visibility` to the Team schema:
- `"private"` (default): `/teams/:id` requires authentication. Only participants (users with a token in token_teams) can view.
- `"public"`: `/teams/:id` is viewable by anyone. Shows team config (name, members, skills, knowledge). Does NOT show invites, participants, or machines.

The visibility setting is changeable by authenticated participants on the team detail page.

### 2. Team slug

Add `slug` to the Team schema. Optional, unique, URL-friendly string. Public teams can have a human-readable URL: `/teams/my-cool-team` in addition to `/teams/:uuid`.

Rules:
- 3-64 chars, lowercase alphanumeric + hyphens, must start with a letter
- Unique across all teams
- Optional (UUID always works)
- Only settable on public teams

### 3. Clone token

Add a `clone_token` field to the Team schema. A random, non-expiring token that grants read-only access to the team config.

- Format: `trc_cl_<random>` (distinct from invite codes `trc_inv_`)
- Only generated for public teams (or on demand)
- Does NOT create a token_team record
- Can be regenerated (invalidates old one)
- Used by: CLI `teamrc clone trc_cl_...`, and shown on the public team page

This replaces the current pattern of using invite codes for cloning. Clone tokens don't expire and don't grant sync access.

### 4. What's shown where

#### `/teams/:id` (private team, unauthenticated)
- Redirect to sign-in, or show "This team is private" message

#### `/teams/:id` (private team, authenticated non-participant)
- "This team is private. You need an invite to join."

#### `/teams/:id` (private team, authenticated participant)
- Full team config (name, members, skills, knowledge)
- Edit controls
- Invites section
- Participants section
- No machines section (machines live on `/dashboard` only)

#### `/teams/:id` (public team, anyone)
- Read-only team config (name, members, skills, knowledge)
- "Clone this team" button with CLI command
- No invites, no participants, no machines, no edit controls

#### `/teams/:id` (public team, authenticated participant)
- Same as private participant view, plus visibility toggle

#### `/dashboard` (authenticated)
- Your machines with hostnames, tokens, revoke controls
- Your teams with machine counts, last seen times
- Links to `/teams/:id`

### 5. Invite flow changes

Invites remain the same mechanically (expiring codes for sync access), but:
- Invite codes are NEVER shown on the public team page
- `/invite/:code` still redirects to `/teams/:id?invite=CODE`
- The `?invite=CODE` param auto-shows the join command to the visitor (existing behavior)

### 6. API changes

New endpoint:
- `GET /api/teams/clone/:clone_token` — returns team config (read-only, no auth required)

Modified:
- `POST /api/teams` — accepts optional `visibility` and `slug` fields
- Team update endpoints accept `visibility` and `slug`

### 7. CLI changes

- `teamrc clone` accepts both `trc_inv_...` (existing, calls preview_by_invite) and `trc_cl_...` (new, calls clone endpoint)
- `teamrc clone <slug-or-url>` could also work for public teams (stretch goal)
- No changes to `teamrc join` (still requires invite code)

### 8. Rename `can_edit_owner` to `can_edit`

It was always just "is authenticated participant." The variable name lies. Rename throughout team_detail_live.ex.

## Schema Changes

### Migration: add visibility, slug, clone_token to teams

```elixir
alter table(:teams) do
  add :visibility, :string, default: "private", null: false
  add :slug, :string
  add :clone_token, :string
end

create unique_index(:teams, [:slug], where: "slug IS NOT NULL")
create unique_index(:teams, [:clone_token], where: "clone_token IS NOT NULL")
```

### Team changeset update

```elixir
field :visibility, :string, default: "private"
field :slug, :string
field :clone_token, :string

def changeset(team, attrs) do
  team
  |> cast(attrs, [:name, :skills, :platforms, :knowledge, :visibility, :slug, :clone_token])
  |> validate_required([:name])
  |> validate_inclusion(:visibility, ["public", "private"])
  |> validate_format(:slug, ~r/^[a-z][a-z0-9-]{2,63}$/)
  |> unique_constraint(:slug)
  |> unique_constraint(:clone_token)
end
```

## Implementation Phases

### Phase 1: Clean up current code
- Remove machines section from team_detail_live.ex (done)
- Rename `can_edit_owner` to `can_edit` in team_detail_live.ex
- Remove unused functions (truncate_token, time_ago — done)
- Simplify `load_team_machines` to `load_team_tokens` (done)

### Phase 2: Schema + migration
- Add visibility, slug, clone_token to Team schema
- Write migration
- Update changeset with validation

### Phase 3: Access control on `/teams/:id`
- team_detail_live mount checks visibility
  - Private + no auth → "This team is private" page
  - Private + auth but not participant → "Need an invite" page
  - Private + participant → full edit view (existing)
  - Public + not participant → read-only view
  - Public + participant → full edit view
- Add visibility toggle to edit controls (participants only)

### Phase 4: Clone token + API
- Generate clone_token when team is set to public
- `GET /api/teams/clone/:clone_token` endpoint
- Show clone command on public team page
- CLI: `teamrc clone` accepts `trc_cl_...` tokens

### Phase 5: Slug support
- Add slug field to team creation/edit UI
- Route `/teams/:id_or_slug` resolves slug first, falls back to UUID
- Public team page shows the slug URL as the shareable link

### Phase 6: Guide + docs update
- Update guide_live.ex web UI section
- Update FAQ
- Update mockups for public vs private views

## Open Questions

1. **Should existing teams default to private or public?** Private is safer. Existing behavior (public by UUID) changes, but there are no prod users yet.

2. **Should the team creation wizard ask about visibility?** Could be a simple toggle: "Make this team public" with a note about what that means. Default off.

3. **Should public teams show up in a directory/gallery?** Not now, but the slug makes it possible later.

4. **Rate limiting on clone endpoint?** Yes, same as other API endpoints. Clone tokens are long random strings so not brute-forceable.

5. **Can a private team have a clone token?** No. Clone tokens only make sense for public teams. Setting visibility to private should clear the clone token.
