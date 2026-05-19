# Task 004: Per-place dashboard

**Status**: OPEN (HOLD until task 003 lands)
**Owner**: Fresh Claude Code session
**Created**: 2026-05-19

## Goal

Replace the `PlaceDetailPlaceholder` stub with a real per-place dashboard: place metadata, RTMPS broadcast credentials (with copy buttons), listener URL + QR, stream-status indicator, broadcaster-side controls (go live from this device — placeholder for ReplayKit until that's wired). Mirror the surface area of the web `/broadcaster/[slug]` dashboard at a high level, native idioms.

## Context

After task 003 lands, signed-in users can list places + create them. The next blocker is "I created a place, now how do I broadcast?" The web dashboard at `app/broadcaster/[slug]/BroadcasterDashboard.tsx` is organized into `SectionGroup`s: Now / Stream / Audience / Money / Distribution / Plan / Help. The native version doesn't need to mirror all sections — focus on Stream + Distribution first.

### What's needed first cut

- **Place metadata** — name, slug, tagline, accent (use accent in section dividers / live indicator)
- **Stream credentials** — RTMPS URL + stream key. From `Place.whip_url` / `Place.playback_url` + a server-side credentials fetch. Read [`Here-Audio/app/api/places/[slug]/stream/route.ts`](https://github.com/hbeyen/Here-Audio/blob/main/app/api/places/%5Bslug%5D/stream/route.ts) — **READ-ONLY** — for the endpoint shape.
- **Listener URL** + QR — `https://here-audio.henock-23c.workers.dev/<slug>`. Generate QR client-side (use `CoreImage`'s `CIFilter.qrCodeGenerator()`)
- **Stream status** — poll `/api/stream-status?slug=<slug>` (or whatever the endpoint is — check Here-Audio's surface)
- **Go live from this device** — placeholder card. Real ReplayKit integration is a follow-up task.

### Architecture

Backend talk-to:
- Read: PostgREST direct + Bearer auth (matches PlacesService.list pattern from task 001)
- Write/sensitive: Cloudflare worker /api/* with Bearer auth

For this task: just reads. Streams credentials should be fetched via the worker (sensitive) — read the route file to confirm.

## Steps

(Pending task 003 merge — until then, the per-place navigation target doesn't exist yet on the iOS side.)

1. **Read `Here-Audio/app/api/places/[slug]/stream/route.ts`** for the credentials endpoint shape
2. **`PlaceService.streamCredentials(slug:)`** — GET via worker, returns RTMPS URL + key
3. **`PlaceDashboardViewModel`** — loads place + streamCredentials in parallel via `async let`
4. **`PlaceDashboardView`** — `Form` or `List` with sections: Now (live dot, listener count placeholder), Stream (RTMPS URL + key with copy buttons), Distribution (QR + listener URL + Share Sheet), Settings (link to place edit — defer; also link to per-place delete — defer)
5. **QR generation** — CoreImage `CIQRCodeGenerator`, scale to ~200pt with high error correction so it's readable on a printed sign
6. **Copy-to-pasteboard** for RTMPS URL + key — short-lived "Copied" toast
7. **Share sheet** for listener URL — UIActivityViewController / SwiftUI `ShareLink`
8. **Wire from PlacesView**: tapping a row routes to `PlaceDashboardView(place: place)` (replaces `PlaceDetailPlaceholder`)
9. **Verify**: build clean, navigate from Places → tap a place → see real RTMPS info

## Acceptance

- `xcodebuild` simulator clean
- From a signed-in account with at least one place, tapping the place row shows real RTMPS credentials, QR for the listener URL, and the share-sheet flow works
- Copy buttons put the right value on the pasteboard
- No force-unwraps

## Out of scope

- ReplayKit broadcast extension wiring (separate task)
- Edit / delete place (separate)
- Listener-count live updates (Realtime — defer)
- Reactions / announcements / tips / ticketing
- Tier display, billing portal link — Settings owns those (already exists from task 001's Settings scene)

## How to report back

Same format. Under 400 words.
