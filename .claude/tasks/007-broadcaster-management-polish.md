# Task 007: Broadcaster management polish (editable display name, edit place, delete place)

**Status**: OPEN
**Owner**: Fresh Claude Code session / subagent
**Created**: 2026-05-19

## Goal

Three small, independent, simulator-testable improvements to broadcaster management — none touch Cloudflare Stream:

1. **Editable display name** in Settings (the Profile section currently shows only the Apple private-relay email like `j6dkmszm6z@privaterelay.appleid.com` because the name-persist only fires on a user's first-ever Apple auth).
2. **Edit place metadata** — rename + change tagline + change accent on an existing place.
3. **Delete place** — remove a place (clears accumulating dev-stub test rows).

## Context

After tasks 001–005, the native app does sign-in → places list → create → dashboard → settings/sign-out. The gaps this task fills came out of on-device testing (2026-05-19): no way to set a display name once Apple has stopped returning the name, no way to fix a typo'd place, no way to delete test places.

### Existing pieces

- `Here/Scenes/Settings/SettingsView.swift` — Profile (email), Account (sign-out), About (version). Add an editable display-name row to Profile.
- `Here/Common/Services/SessionService.swift` — holds `displayName`. Has the Supabase access token. The display name persists via Supabase user_metadata.
- `Here/Common/Auth/SupabaseAuthClient.swift` — talks to Supabase Auth REST. To persist a custom display name, PATCH `https://xiqyaryjagujgsxcuabb.supabase.co/auth/v1/user` with body `{ "data": { "full_name": "<name>" } }`, headers `apikey: <anon>` + `Authorization: Bearer <access_token>`. (This is the REST equivalent of `supabase.auth.updateUser({ data: { full_name } })`.) On success, update `SessionService.displayName` + the local session.
- `Here/Common/Services/PlacesService.swift` — `list()`, `fetch(slug:)`, `create(...)`. Add `update(...)` and `delete(...)`.
- `Here/Common/Models/Place.swift` — the 6-field model. May widen if edit needs more fields.
- `Here/Scenes/Place/PlaceDashboardView.swift` — the per-place screen. Add an Edit affordance (top-right, or a row) → presents an edit sheet. Add a Delete affordance (destructive, with confirmation).

### Reads/writes — follow the established pattern

Per the CONDUCTOR.md decisions log:
- **Reads** go to Supabase PostgREST direct (anon JWT + Bearer access token, RLS owner-scoped).
- **Metadata writes** (rename/tagline/accent) — the `places` table has RLS `places_owner_update` + `places_owner_delete` policies (verify in `Here-Audio/docs/sql/002_places.sql`, READ-ONLY). So a PostgREST `PATCH /rest/v1/places?slug=eq.<slug>` and `DELETE /rest/v1/places?slug=eq.<slug>` work with the user's access token — no worker needed for metadata.
- **BUT for delete**: a real Cloudflare Stream Live Input would be orphaned if you only delete the DB row. Check whether `Here-Audio/app/api/places/[slug]/route.ts` (or similar) exposes a worker `DELETE` that also cleans up the Cloudflare input (READ-ONLY — read it to decide). Prefer the worker DELETE if it exists (it cleans up the input); fall back to PostgREST DELETE if not. For now every place is a dev-stub or failed-provision so there's nothing real to clean, but build it right.

## Steps

1. **Display name**:
   - `SupabaseAuthClient.updateDisplayName(_ name: String) async throws` — PATCH `/auth/v1/user` with `{ data: { full_name } }`.
   - `SessionService` gains a method to call it + update local `displayName`.
   - `SettingsView` Profile section: add a "Display name" row. Tappable → inline edit or a small sheet with a TextField + Save. Pre-fill with current display name (falls back to empty if only email). On save, call through and reflect immediately.

2. **Edit place**:
   - `PlacesService.update(slug:name:tagline:accent:) async throws -> Place` — PostgREST PATCH, returns the updated row (use `Prefer: return=representation` header).
   - New scene `Here/Scenes/EditPlace/EditPlaceView.swift` + ViewModel, OR reuse the NewPlace form components for consistency (your call — document it). Fields: name, tagline, accent. (Slug + geofence editing are OUT of scope — slug is the identity, geofence editing is a bigger MapKit task.)
   - `PlaceDashboardView`: add an "Edit" button → presents the edit sheet → on save, refresh the dashboard's place.

3. **Delete place**:
   - `PlacesService.delete(slug:) async throws` — worker DELETE if available, else PostgREST DELETE.
   - `PlaceDashboardView`: destructive "Delete place" row at the bottom → confirmation alert ("Delete <name>? This can't be undone.") → on confirm, delete → pop back to Places list → refresh so the row disappears.

4. **Verify on simulator**:
   - Settings → set a display name → confirm it shows (and survives app relaunch via the persisted metadata + Keychain session).
   - Dashboard → Edit → rename a place → confirm the list + dashboard reflect it.
   - Dashboard → Delete → confirm → place gone from the list.
   - Web cross-check (optional): the same account on `/broadcaster` web shows the rename/deletion.

5. **Commit + push** on `claude/broadcaster-management-polish`. PR title `feat: editable display name + edit/delete place`.

## Acceptance

- `xcodebuild ... -destination "generic/platform=iOS Simulator" build` clean (CI will also gate this now).
- Display name editable + persists across relaunch.
- Place rename + accent/tagline edit works and reflects everywhere.
- Place delete works with confirmation, removes the row.
- No force-unwraps; two-space indent; no snake_case CodingKeys (use the decoder strategy — see CLAUDE.md).

## Out of scope

- Slug editing (it's the identity).
- Geofence editing (bigger MapKit task — separate brief if wanted).
- Avatar upload.
- ReplayKit / broadcasting (task 006).
- Anything that requires Cloudflare Stream to be enabled.

## How to report back

Same format. PR URL, files added/modified, punted items, design judgments not in the brief, watch-outs. Under 350 words.
