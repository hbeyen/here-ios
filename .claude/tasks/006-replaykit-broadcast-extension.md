# Task 006: ReplayKit broadcast extension (the actual broadcasting feature)

**Status**: HOLD — do not dispatch until Cloudflare Stream is enabled on the account (so there's a real WHIP endpoint to test against). Build-and-compile is possible without it, but end-to-end audio testing is not, and building a complex WebRTC audio pipeline blind accumulates latent bugs. Wait for the green light from the conductor.
**Owner**: Fresh Claude Code session / subagent (needs device + Xcode iteration)
**Created**: 2026-05-19

## Goal

Wire system-audio broadcasting into the native app: tap "Broadcast from this device" on `PlaceDashboardView` → iOS broadcast picker → pick HERE → the ReplayKit Broadcast Upload Extension captures system audio (Spotify/SoundCloud/etc.) and pushes it via WebRTC/WHIP to the place's Cloudflare Stream Live Input → a listener on `/<slug>` hears it.

This is THE reason the native app exists. Everything else (auth, places, dashboard) is scaffolding around this.

## Context

The Capacitor wrapper (in `Here-Audio/ios/App/BroadcastUpload/` and `native/ios/`) already proved this architecture and has working-compiling Swift sources. **These are READ-ONLY reference in the Here-Audio repo — copy the patterns, type fresh into here-ios.** Specifically:

- `Here-Audio/ios/App/BroadcastUpload/SampleHandler.swift` — the extension entry point. Receives `CMSampleBuffer` audio from ReplayKit, owns the WebRTC peer connection, does the WHIP SDP exchange against the place's WHIP URL.
- `Here-Audio/ios/App/BroadcastUpload/AppAudioCapturer.swift` — converts ReplayKit's `CMSampleBuffer` → PCM frames for WebRTC.
- `Here-Audio/ios/App/BroadcastUpload/CustomAudioDevice.swift` — custom `RTCAudioDevice` feeding the capturer's frames into WebRTC's pipeline. **Note: this was rewritten for the stasel/WebRTC 130.x ADM block API (see Here-Audio CONDUCTOR / commit history). Pin WebRTC-SDK 130.0.0–131.0.0, same as the Capacitor build.**
- `Here-Audio/ios/App/App/HereBroadcastPlugin.swift` — the Capacitor plugin that triggered `RPSystemBroadcastPickerView`. In native, this becomes a regular `BroadcastService` Swift class (no Capacitor bridge) called from SwiftUI.
- `Here-Audio/native/ios/SETUP.md` — the Xcode wiring walk-through (target creation, App Group, entitlements, WebRTC SPM).

### Key architecture facts (carried over from the Capacitor build)

- **WHIP, not RTMPS, for the iOS device path.** ReplayKit → WebRTC → WHIP ingest at Cloudflare Stream. The place's `whip_url` comes from the credentials (`StreamCredentialsService` from task 004 already fetches `webRTC.url`).
- **App Group** (`group.fm.here.app.broadcast`) shares the WHIP URL from the host app to the extension process (they're separate processes). The host writes the WHIP URL to the shared `UserDefaults(suiteName:)`; the extension reads it.
- **WebRTC-SDK 130.x via SPM**, added to the BroadcastUpload target only.
- **No token exchange backend** — the WHIP URL itself is the credential. The host fetches it via `StreamCredentialsService`, writes it to the App Group, the extension reads + POSTs the SDP.

## Steps (high level — flesh out from the Capacitor reference)

1. **New extension target** in `project.yml`: a Broadcast Upload Extension (`BroadcastUpload`), bundle `fm.here.app.BroadcastUpload`, embedded in the Here app. xcodegen supports extension targets — define it in `project.yml` and `xcodegen generate`.
2. **Port the Swift sources** (typed fresh, not copied from Here-Audio): `SampleHandler.swift`, `AppAudioCapturer.swift`, `CustomAudioDevice.swift` into the extension target. Keep the WebRTC 130.x ADM API shape — the Here-Audio version is the known-good reference.
3. **App Group** `group.fm.here.app.broadcast` capability on BOTH the Here app target and the BroadcastUpload target. Entitlements in `project.yml`.
4. **WebRTC-SDK SPM dependency** pinned to `130.0.0..<131.0.0`, on the BroadcastUpload target only.
5. **`BroadcastService`** in the host app (`Here/Common/Services/BroadcastService.swift`):
   - `func startBroadcast(whipURL: URL)` — writes the WHIP URL to the App Group `UserDefaults`, then presents `RPSystemBroadcastPickerView` (programmatically tap its button, same trick as `HereBroadcastPlugin`).
   - `func broadcastState() -> ...` — poll the App Group for state the extension writes back.
6. **Wire into `PlaceDashboardView`** — the "Broadcast from this device" card (currently a placeholder) calls `BroadcastService.startBroadcast(whipURL:)` with the place's `webRTC.url` from its credentials. Show broadcast state (idle / connecting / live / error).
7. **NSMicrophoneUsageDescription** — already in `project.yml` info.properties. ReplayKit system-audio doesn't strictly need mic, but keep it for the mic fallback path.
8. **Build + device test** (NOT simulator — ReplayKit broadcast needs a real device):
   - Build to iPhone, trust profile
   - Open a place dashboard → tap Broadcast → iOS picker → pick HERE → Start Broadcast
   - Play music in Spotify
   - On a second device / browser, open the listener URL → confirm audio
9. **Iterate** — the `CustomAudioDevice` / WebRTC ADM integration is the part most likely to need on-device debugging. The Here-Audio version compiled but was never verified end-to-end (Stream was never enabled there either), so expect to debug the actual audio flow.

## Acceptance

- `xcodebuild` builds both the Here app + BroadcastUpload extension
- On a real iPhone: broadcast picker shows HERE, system audio from Spotify reaches a listener on `/<slug>`
- Stopping the broadcast cleans up the WHIP connection
- No force-unwraps; two-space indent

## Out of scope

- Mic-only broadcast mode (system audio is the point; mic is a fallback for later)
- DRM-protected apps (Apple Music / Podcasts — known iOS limitation; iRig hardware is the documented workaround on the web `/guide`)
- Broadcast scheduling, multi-source mixing
- Android

## Prerequisites before dispatch

1. **Cloudflare Stream enabled** on the account (so `whip_url` is real, not null) — currently blocked.
2. A place that has a real Live Input (created AFTER Stream is enabled) to test against.
3. The conductor confirms #1 + #2 before dispatching this.

## How to report back

PR URL, the extension target + Swift files, the WebRTC integration state, what worked on device vs. what needed debugging, watch-outs. This one will likely need multiple device-test iterations — report the state honestly even if not fully working, so the conductor can dispatch follow-ups.
