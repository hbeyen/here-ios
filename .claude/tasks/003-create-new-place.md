# Task 003: Create new place flow

**Status**: OPEN
**Owner**: Fresh Claude Code session
**Created**: 2026-05-19

## Goal

Wire the "Create your first place" CTA on `PlacesView` to a `NewPlaceView` that lets the user name the place + drop a circular geofence on a MapKit map, then POST to `/api/places` on the Cloudflare worker. On success, route back to the Places list (the new place appears) and disable the empty-state CTA in favor of an "+ New place" affordance.

## Context

PR #3 (`26075b0`) shipped the SignIn → Places-list loop. The empty-state CTA is currently rendered but disabled with `.opacity(0.55)`. A signed-in user with zero places is therefore stuck — this task unblocks them.

### Write-path architecture

POST/DELETE go through the Cloudflare worker because the worker provisions external resources (Cloudflare Stream Live Inputs):

- Endpoint: `POST https://here-audio.henock-23c.workers.dev/api/places`
- Read [`~/Developer/Here-Audio/app/api/places/route.ts`](https://github.com/hbeyen/Here-Audio/blob/main/app/api/places/route.ts) — **READ-ONLY**, do not write into Here-Audio. It will tell you the expected request body shape, the response shape, and any validation rules.
- Auth: `Authorization: Bearer <access_token>` (same as the list call)
- Response includes the newly-created place plus stream credentials (RTMPS URL + stream key) — but those credentials are the per-place dashboard's concern (task 004). For this task, take the place's `slug` and route back to Places list.

### Geofence shape

The web broadcaster lets the user draw a polygon. For the iOS app's v0.3 entry point, **circle only** (center lat/lng + radius in meters). The web side already accepts polygon-encoded-as-circle; here's the GeoJSON to send:

```json
{
  "type": "Polygon",
  "coordinates": [[
    [lng1, lat1], [lng2, lat2], ..., [lng1, lat1]
  ]]
}
```

Generate ~32 points around the circle and close the ring. The web's `lib/geofence.ts` accepts this. Smaller `n` is fine; 16+ keeps it visually round.

### MapKit + permission

Use SwiftUI's `Map { ... }` (iOS 17 MapKit-SwiftUI integration). The `NSLocationWhenInUseUsageDescription` is already set in `project.yml`. On the create-place screen, request location permission via `CLLocationManager.requestWhenInUseAuthorization()` — center the map on the user's location once granted, with a draggable annotation in the middle and a slider for radius (default ~30m, range 10–500m).

If permission is denied, center the map on a sensible default (San Francisco?) and let the user drag a pin to wherever they want. Don't block the flow on location permission.

## Steps

1. **Read [`Here-Audio/app/api/places/route.ts`](https://github.com/hbeyen/Here-Audio/blob/main/app/api/places/route.ts)** to confirm the POST body shape. Note: the route is Next.js `Route Handler` style, returns `NextResponse.json(...)`.

2. **`PlacesService.create(...)`** — new method:
   - Signature: `func create(name: String, slug: String, tagline: String?, accent: String, geofence: GeoJSONPolygon) async throws -> Place`
   - POSTs to `/api/places` with the worker URL
   - Use `APIClient` (existing) with Bearer auth from `SessionService`
   - Decodes the returned Place row into the existing `Place` model — may need to widen `Place` to include new fields the response returns (especially anything we'll need for the per-place dashboard later)

3. **New scene `NewPlace`**:
   - `Here/Scenes/NewPlace/NewPlaceView.swift`
   - `Here/Scenes/NewPlace/NewPlaceViewModel.swift`
   - State: form fields (name, slug auto-derived from name with override toggle, tagline, accent color), geofence (lat, lng, radius), `isSubmitting`, `error`
   - UI: scrolling Form, sections for Identity (name, slug, tagline, accent), Geofence (MapKit map + radius slider). Submit button at bottom, disabled until name + slug + center are set.
   - On submit: build the GeoJSON polygon (32-point approximation of the circle), call `PlacesService.create(...)`, on success dismiss back to PlacesView (force a refresh so the new place appears).

4. **`PlacesView`** wiring:
   - Replace the disabled empty-state CTA with a working `NavigationLink` (or sheet — your call, document) to NewPlaceView
   - Add a "+ New place" toolbar button when the list is non-empty (top-right, gear stays where it is)
   - On dismiss from NewPlace, the ViewModel should re-fetch

5. **`Place` model** — widen if the POST response carries fields not in the read shape. Document any additions in the PR body.

6. **Accent color picker** — minimal: a horizontal scroll of preset swatches (~8 colors that match the existing HERE brand vibes). Don't ship a full ColorPicker — that's UX scope creep.

7. **Slug validation** — server enforces uniqueness; surface 409 errors gracefully ("That slug is taken — try another"). For client-side, just lowercase + replace non-alphanumeric with `-`.

8. **Verify on simulator**: build clean, sign in, tap "Create your first place", fill the form, submit, see the new place appear in the list. Verify on the web that the place exists (signing into `/broadcaster` on web should show the same row).

9. **Commit + push** on `claude/create-new-place`, open PR titled `feat: create new place flow (MapKit geofence + POST /api/places)`.

## Acceptance

- `xcodebuild -project Here.xcodeproj -scheme Here -configuration Debug -destination "generic/platform=iOS Simulator" build` clean
- Sign in → empty state → tap "Create your first place" → fill form → submit → land back on Places list with the new place visible
- Same Apple ID, signing into `/broadcaster` on web (mobile Safari or desktop), shows the new place
- No force-unwraps; two-space indent; commit author Henock Beyen

## Out of scope

- Polygon (non-circular) geofence — circle only for v0.3 entry
- Per-place dashboard / detail view — task 004 covers it; for now tapping a place row goes to `PlaceDetailPlaceholder`
- ReplayKit / broadcasting from the new place — separate task
- Edit place / delete place — defer
- Tier-cap enforcement client-side (server already enforces; just surface the error message if it returns 402)
- Stripe Connect onboarding inside the wizard

## How to report back

Same format as task 001: PR URL, files added/modified, punted items, design judgments not in the brief, things future-you should watch for. Under 400 words.
