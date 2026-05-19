# Task 001: SignIn → Places list end-to-end

**Status**: OPEN
**Owner**: Fresh Claude Code session
**Created**: 2026-05-18

## Goal

Make the existing SwiftUI scaffold actually work: sign in via Apple, exchange the identity token with Supabase, fetch the user's places from `/api/places`, render them in `PlacesView`. Sign out from a settings sheet returns to /sign-in. Session survives app relaunch via Keychain-stored refresh token.

## Context

PR #1 (`fe1da51` on main) shipped the architecture scaffold:

- `Here/App/AppCoordinator.swift` routes to `SignInView` when unauthenticated, `PlacesView` when authenticated
- `Here/Scenes/SignIn/` has working SiwA via `AppleSignInController` + `SupabaseAuthClient.signInWithIdToken`
- `Here/Common/Services/SessionService.swift` holds auth state, stores tokens in Keychain
- `Here/Scenes/Places/PlacesView.swift` is a placeholder — shows "You're signed in" with the display name
- `Here/Common/Networking/APIClient.swift` is the URLSession + Codable foundation

The missing pieces:

1. **`HERE_SUPABASE_ANON_KEY` isn't wired yet** — `SupabaseAuthClient` reads it from `Bundle.main.infoDictionary` but the value isn't in `project.yml`. Without it, SiwA fails when it tries to call Supabase.
2. **No `PlacesService`** — nothing actually calls `/api/places` yet.
3. **No `Place` model** — need to mirror the response shape from `Here-Audio/app/api/places/route.ts` (read-only reference, don't write into Here-Audio).
4. **`PlacesView` is a placeholder** — needs to become a real list view backed by a ViewModel.
5. **No sign-out path** — `SessionService.signOut()` exists but isn't wired to any UI.
6. **No settings UI** — need a minimal Settings scene with at least a Sign Out button + maybe display name + version.

### Anon key — safe to commit

The Supabase **anon** key is the same `NEXT_PUBLIC_SUPABASE_ANON_KEY` that Here-Audio ships in its client bundle (it's a public key, distinct from the `SUPABASE_SERVICE_ROLE_KEY` which is server-only). It's safe to commit to this repo. Pull the value from `~/Developer/Here-Audio/.env.example` references or from Cloudflare Workers env var `NEXT_PUBLIC_SUPABASE_ANON_KEY`. Set it as a `project.yml` build setting that lands in Info.plist:

```yaml
settings:
  base:
    INFOPLIST_KEY_HERE_SUPABASE_ANON_KEY: "eyJ..."
```

(or via xcconfig — your call; document the choice in CLAUDE.md).

### Endpoint shape

`/api/places` on the backend returns the user's owned places (gated by Supabase auth). Read `~/Developer/Here-Audio/lib/places-server.ts` for the `Place` zod schema. Likely fields: `id`, `slug`, `name`, `tagline`, `accent`, `geofence`, `playback_url`, `whip_url`, `stage`, `channels`, `subzones`, `schedule`, `highlights`, `stripe_account_id`, `tip_recipient`, `ticket`, `is_active`, `created_at`. **Mirror minimally** — only decode the fields you actually display. Add more as later tasks need them.

Auth header: `Authorization: Bearer <access_token>` from `SessionService`.

### Reference repos

- `~/Desktop/GitHub/Says/Says-iOS/` — read-only architecture reference (see how their feed-list scenes wire ViewModel → UseCase → Service)
- `~/Developer/Here-Audio/` — read-only context for endpoint shapes only. **Don't write into this repo from task 001.**

## Steps

1. **Wire `HERE_SUPABASE_ANON_KEY`** in `project.yml` so it's available via `Bundle.main`. Run `xcodegen generate` to regenerate the Xcode project. Verify `SupabaseAuthClient` reads it successfully.

2. **Define `Place` model** (`Here/Common/Models/Place.swift`) — Codable struct mirroring `/api/places` response. Start minimal (id, slug, name, tagline, accent, is_active). Add fields as PlacesView needs them.

3. **Implement `PlacesService`** (`Here/Common/Services/PlacesService.swift`):
   - `func list() async throws -> [Place]`
   - Uses `APIClient` + `SessionService`'s access token
   - Handles 401 by signaling SessionService to sign out (refresh-token rotation is out of scope for this task — if access token expires, user re-signs-in)
   - Register in `Locator+Dependencies.swift`

4. **Implement `PlacesViewModel`** (`Here/Scenes/Places/PlacesViewModel.swift`):
   - `@Observable` (matches the existing convention)
   - `@MainActor`
   - State: `var places: [Place] = []`, `var isLoading: Bool = true`, `var error: String? = nil`
   - Method: `func load() async` — calls `PlacesService.list()`
   - Method: `func refresh() async` — same, for pull-to-refresh
   - Use `@Locatable` to resolve PlacesService

5. **Build `PlacesView`** (`Here/Scenes/Places/PlacesView.swift`):
   - Replace the placeholder
   - Header: "Your places" + signed-in user's display name + Settings gear top-right
   - Loading state: spinner
   - Empty state: "Create your first place" CTA (button is non-functional — task 002 will wire it)
   - List of places: name + slug + accent dot (one row per place, tappable but routes to a `Text("Place: \(name)")` placeholder)
   - Pull-to-refresh calls `viewModel.refresh()`

6. **Build `SettingsView`** (`Here/Scenes/Settings/SettingsView.swift` — new scene):
   - `Form` with sections: Profile (display name, email), Account (Sign Out button)
   - Sign Out: tap → confirmation alert → call `SessionService.signOut()` → routes back to /sign-in via AppCoordinator
   - Optional: About section with `Bundle.main.infoDictionary["CFBundleShortVersionString"]`

7. **Update `AppCoordinator`** if needed so Settings can present as a sheet from PlacesView and dismiss back. SwiftUI-flavored — use `NavigationStack` + `.sheet(isPresented:)` or push as a destination, whichever feels cleaner.

8. **Verify on simulator**: `xcodebuild -destination "generic/platform=iOS Simulator" build` clean. Then `open Here.xcodeproj`, run on iPhone 17 Pro simulator, sign in with an Apple ID, confirm:
   - Sign in completes without errors
   - Places list appears (empty if no places on this account)
   - Settings → Sign Out → returns to /sign-in
   - Quit + relaunch → if refresh token works, stays signed in; otherwise prompts sign in

9. **Update `here-ios/CLAUDE.md`** to document the anon-key wiring choice.

10. **Commit + push** on branch `claude/places-list-real-api`. Open PR with title `feat: SignIn → Places list end-to-end with real /api/places`. Squash-merge to main is the convention.

## Acceptance

- `xcodebuild -project Here.xcodeproj -scheme Here -destination "generic/platform=iOS Simulator" build` clean
- Sign in via Apple succeeds (Apple sheet → Face ID → land on Places)
- Places list renders real data from `/api/places` (or correct empty state)
- Sign Out from Settings clears Keychain + Supabase session + routes to /sign-in
- App relaunch: if refresh-token logic isn't implemented yet, user re-signs-in cleanly; no crash
- No force-unwraps in production paths
- `CLAUDE.md` documents the anon-key wiring

## Out of scope

- Per-place detail view / dashboard (next task)
- Create new place flow
- Edit place
- Refresh-token rotation (if access token expires mid-session)
- ReplayKit broadcast extension
- Fastlane / TestFlight
- Anything in Here-Audio repo

## How to report back

When the PR is open + ready for the conductor to merge, post in the conductor chat:

- PR URL
- File tree of what shipped (added vs modified)
- Anything you punted on (be explicit — even if it's "Place model only has 6 fields, full schema deferred")
- Design judgments not in this brief (e.g. "Used `NavigationStack` push instead of sheet for Settings because…")
- Anon-key wiring choice + how to verify
- What broke during dev that future-you should watch for
