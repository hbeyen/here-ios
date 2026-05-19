# Task 004: Per-place dashboard

**Status**: OPEN (unblocked — task 003 merged via PR #5)
**Owner**: Fresh Claude Code session
**Created**: 2026-05-18 (revised 2026-05-19)

## Goal

Replace the `PlaceDetailPlaceholder` stub with a real per-place dashboard. The user can: see the place's metadata (name, slug, tagline, accent), copy the RTMPS broadcast credentials, scan/share the listener-URL QR code, and see a placeholder "Go live from this device" card (real ReplayKit integration is a follow-up task).

## Context

After tasks 001 + 003, the iOS flow is: sign in → places list → tap a row → `PlaceDetailPlaceholder`. This task replaces the placeholder with the real dashboard. Mirrors the web `/broadcaster/[slug]` surface at a high level using native iOS idioms (no `Form` — match `PlacesView`'s custom dark-theme aesthetic).

### Architecture — Place + credentials are separate resources

Per the architectural decision logged in [`.claude/CONDUCTOR.md`](../CONDUCTOR.md) (2026-05-19), **Place metadata** and **stream credentials** are fetched independently:

- **Place metadata** — read via Supabase PostgREST direct (`GET https://xiqyaryjagujgsxcuabb.supabase.co/rest/v1/places?slug=eq.<slug>` with anon JWT + Bearer auth). RLS enforces owner scoping. Add `PlacesService.fetch(slug:) async throws -> Place`.
- **Stream credentials** — read via the Cloudflare worker (`GET https://here-audio.henock-23c.workers.dev/api/places/{slug}/stream` with Bearer auth). Returns RTMPS URL + stream key + WHIP URL + playback URL. Read [`Here-Audio/app/api/places/[slug]/stream/route.ts`](https://github.com/hbeyen/Here-Audio/blob/main/app/api/places/%5Bslug%5D/stream/route.ts) — **READ-ONLY** — for the exact shape. Add a new service: `StreamCredentialsService.fetch(slug:) async throws -> StreamCredentials`.

Two entry points to the dashboard:

1. **From the Places list tap** — `PlacesView` already has the `Place` row in hand. Pass it into `PlaceDashboardView(place: place)`. Dashboard fetches credentials on view-load. Place metadata is already present so no second fetch needed for refresh on a snappier UX (still expose pull-to-refresh that triggers both Place + credentials).
2. **From a "just created" deep-link** — `NewPlaceView`'s create-flow currently returns `CreatePlaceResponse { slug, rtmps, webRTC, playback }` (per PR #5). Pass `slug` + credentials directly into the dashboard. Dashboard fetches the Place metadata on view-load (it isn't in the response shape). Same dashboard view, different presentation context.

In both cases, the dashboard holds both `place: Place` and `credentials: StreamCredentials?` in its ViewModel and either one can be `nil` initially while the corresponding fetch completes. Use `async let` to parallelize where applicable.

### Surface — first cut

Mirror the web's broadcaster dashboard *sections* (not pixel-for-pixel layout):

- **Header**: place name (large), slug under it, accent-colored live dot. Settings gear top-right (already exists from task 001). Back chevron top-left.
- **Stream credentials section** — labelled rows for RTMPS URL + Stream Key. Each row has a copy-to-pasteboard button. Stream key is masked behind a "Show" toggle (hold-to-reveal is overkill for v0.3; tap-to-reveal is fine). Brief "Copied!" toast on tap. Use system pasteboard.
- **Distribution section** — QR for the listener URL (`https://here-audio.henock-23c.workers.dev/<slug>`). Generated client-side via Core Image's `CIFilter.qrCodeGenerator()`. Below the QR: the URL itself in monospace + a Share button (SwiftUI `ShareLink`).
- **Go live section** — placeholder card: "Broadcast from this device". Tappable but routes to a `Text("ReplayKit integration coming in task 005")` placeholder for now. Real integration is a separate task.
- **Plan section** — defer entirely; the existing Settings scene from task 001 owns tier display + billing portal.

### What "credentials" look like

Read [`Here-Audio/app/api/places/[slug]/stream/route.ts`](https://github.com/hbeyen/Here-Audio/blob/main/app/api/places/%5Bslug%5D/stream/route.ts) first — that's the source of truth. Likely shape (from the iOS-side `CreatePlaceResponse`):

```swift
struct StreamCredentials: Decodable {
  let rtmps: String        // e.g. "rtmps://live.cloudflare.com:443/live/"
  let streamKey: String    // long opaque token
  let webRTC: URL?         // optional WHIP URL
  let playback: URL?       // HLS URL for listeners
}
```

Verify field names match the route's response — the brief is approximate.

## Steps

1. **Read `Here-Audio/app/api/places/[slug]/stream/route.ts`** to confirm the credentials response shape. Note: this is a READ-ONLY reference — never write into Here-Audio.

2. **`PlacesService.fetch(slug: String) async throws -> Place`** — PostgREST `GET /rest/v1/places?slug=eq.<slug>&select=*&limit=1`. Decodes the first result into the existing `Place` model. Returns 404 if the row isn't visible (RLS).

3. **`StreamCredentialsService`** — new service in `Here/Common/Services/StreamCredentialsService.swift`:
   - `func fetch(slug: String) async throws -> StreamCredentials`
   - Uses `APIClient` (Bearer auth from `SessionService`) — hits the worker
   - Surface 401 by signaling SessionService to sign out (same pattern as PlacesService.list)
   - Register in `Locator+Dependencies.swift`

4. **`StreamCredentials` model** — Codable struct mirroring the route's response. May share / overlap with the existing `CreatePlaceResponse` from PR #5 — if shapes match, generalize one into the other; if they diverge, keep both with clear names.

5. **`PlaceDashboardViewModel`** — `@Observable @MainActor` class:
   - State: `var place: Place`, `var credentials: StreamCredentials?`, `var isLoadingCreds: Bool`, `var error: String?`, `var streamKeyRevealed: Bool`
   - Init: takes a Place + optional `prefetchedCredentials: StreamCredentials? = nil` so the deep-link-from-NewPlace path can pass creds without a fetch
   - Method: `func load() async` — loads credentials if not already present (and refreshes Place via `PlacesService.fetch` if pull-to-refresh is invoked)
   - Method: `func refresh() async` — full re-fetch (both Place + credentials in parallel via `async let`)
   - Method: `func copyToPasteboard(_ value: String, label: String)` — sets `UIPasteboard.general.string`, exposes a brief "Copied" toast state

6. **`PlaceDashboardView`** — replaces `PlaceDetailPlaceholder`. Custom dark-theme layout matching `PlacesView`. Sections as described above. QR generated inline:

   ```swift
   private func qr(for url: String) -> UIImage? {
     let filter = CIFilter.qrCodeGenerator()
     filter.message = Data(url.utf8)
     filter.correctionLevel = "H"
     // scale up + render to UIImage
   }
   ```

7. **Wire from `PlacesView`** — tapping a row now routes to `PlaceDashboardView(place: place)` (replaces the placeholder). The `NavigationStack` push from PR #3 stays the same; just swap the destination.

8. **Wire from `NewPlaceView`** — after a successful `create(...)`, instead of dismissing the sheet and relying on list-refresh, dismiss + push a `PlaceDashboardView(place: <fetched Place>, prefetchedCredentials: response.credentials)`. The simplest version: dismiss the sheet, then the list refresh picks up the new place + a `selectedPlace` binding on PlacesView opens the dashboard. (If that's too tricky, fine to just dismiss + let user tap the new row — document the choice.)

9. **Verify on simulator**:
   - Sign in → tap a place → dashboard renders place metadata + credentials
   - Copy RTMPS URL — paste into Notes app on simulator, confirm value
   - QR renders — point a real phone camera at the simulator screen, scan, confirm URL opens
   - Show / hide stream key toggle works
   - Pull-to-refresh refetches both Place + credentials in parallel

10. **Commit + push** on `claude/place-dashboard`. Open PR titled `feat: per-place dashboard (credentials, listener QR, share)`.

## Acceptance

- `xcodebuild -project Here.xcodeproj -scheme Here -configuration Debug -destination "generic/platform=iOS Simulator" build` clean
- From the Places list, tapping a place opens a working dashboard with real RTMPS credentials + QR + Share + sign-out path
- Deep-link from NewPlace lands on the dashboard with prefetched credentials (no extra spinner if creds are present at init)
- No force-unwraps; two-space indent; commit author Henock Beyen

## Out of scope

- ReplayKit broadcast extension wiring (the Go-Live placeholder card stays a placeholder — separate task)
- Edit place / delete place (defer)
- Listener-count live updates via Realtime (defer)
- Reactions / announcements / tips / ticketing (defer)
- Tier display + billing portal — Settings owns those (already in task 001's Settings scene)
- "Rotate stream key" button — Phase 3 backend work + separate task

## How to report back

Same format. PR URL, files added/modified, punted items, design judgments not in the brief, things future-you should watch for. Under 400 words.
