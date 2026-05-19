# Here-iOS — Working with this repo

Here-iOS is the **native SwiftUI broadcaster app** for HERE — the geofenced live-audio platform. Backend (Supabase + Cloudflare Stream + Cloudflare Workers) lives in the [hbeyen/Here-Audio](https://github.com/hbeyen/Here-Audio) repo. This repo is iOS-only.

## Why this repo exists

The Capacitor wrapper around the web broadcaster (in `Here-Audio/ios/`) had too many WebView-only UX issues — viewport scroll bounce, FOUC, magic-link cookie splits, manual rebuild of every native primitive. After multiple PRs band-aiding those, we made the architectural call (2026-05-18) to move broadcaster to a true native SwiftUI app while keeping the web for listeners.

- **Listeners** → mobile Safari at `here-audio.henock-23c.workers.dev/<slug>` (no install). Web stays.
- **Broadcasters** → this app, talks to the same /api/* on the Cloudflare worker.

See [hbeyen/Here-Audio/ROADMAP.md](https://github.com/hbeyen/Here-Audio/blob/main/ROADMAP.md) for the cross-stack roadmap.

## Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI (no UIKit unless absolutely needed)
- **Architecture**: MVVM + Coordinator + UseCase + Locator DI (pattern lifted from `~/Desktop/GitHub/Says/Says-iOS/` — read-only reference; never write into that tree)
- **Reactive**: Combine + Swift Concurrency (`async`/`await`) — prefer async/await for new code
- **Min iOS**: 17.0
- **Dependencies**: Swift Package Manager only (no CocoaPods unless forced by a library)
- **Project file**: generated from [`project.yml`](project.yml) via [xcodegen](https://github.com/yonaskolb/XcodeGen). `Here.xcodeproj` IS committed for IDE convenience, but `project.yml` is the source of truth — regenerate with `xcodegen generate` after any structural change.
- **Bundle ID**: `fm.here.app` (reusing the bundle from the retired Capacitor wrapper)
- **Team**: Says, Inc. (`7594TCUA42`)
- **Backend URL**: `https://here-audio.henock-23c.workers.dev/api/*` (production). No local backend setup needed for normal dev — point at prod.

## Commands

```bash
xcodegen generate                          # regenerate Here.xcodeproj from project.yml
open Here.xcodeproj                        # open in Xcode
xcodebuild -project Here.xcodeproj -scheme Here -configuration Debug -destination "generic/platform=iOS Simulator" build
xcodebuild ... -destination "id=<UDID>" -allowProvisioningUpdates build   # device build
xcrun devicectl device install app --device <UDID> Here.app
```

Fastlane comes later (see iOS task tracker once it exists).

## Branch + PR conventions

Same as Here-Audio:
- `main` is production. Don't push directly.
- Feature work on `claude/*` branches. PRs squash-merge.
- Commit author should be Henock Beyen (`hbeyen@gmail.com`).

## Code conventions

- **Two-space indentation** in Swift (matches the existing style in this repo's seed files; Says-iOS uses 4-space — we diverge consciously to match Henock's modern preference).
- **No force-unwraps** (`!`) in production code paths. Use `guard` or optional chaining.
- **Comments only for non-obvious "why"** — same rule as Here-Audio.
- **One type per file** wherever possible (Coordinator, ViewModel, View can co-locate when tightly coupled).
- **No singletons except the DI Locator** — everything else goes through constructor injection or `@Locatable`.

## Reference repos are read-only

`~/Desktop/GitHub/Says/Says-iOS/` is read-only reference. Study patterns. Never write, edit, or git-mutate anything outside `~/Developer/here-ios/`. If a Says pattern should land here, type the equivalent fresh into a here-ios file.

## Architecture (planned — landing in follow-up PRs)

```
Here/
├── App/                          # @main, AppCoordinator, root setup
├── Scenes/
│   ├── SignIn/                   # SiwA, magic-link fallback (web only — native uses SiwA primary)
│   ├── Places/                   # /broadcaster equivalent — places list
│   ├── Place/                    # /broadcaster/[slug] — per-place dashboard
│   ├── NewPlace/                 # /broadcaster/new — create-place wizard
│   ├── Settings/                 # /broadcaster/settings — profile, plan, sign-out
│   └── Broadcast/                # ReplayKit broadcast picker + status
├── Common/
│   ├── Networking/               # URLSession + Codable, REST against /api/*
│   ├── Service/                  # SessionService, PlaceService, BroadcastService
│   ├── Models/                   # Mirror zod schemas from Here-Audio/lib/places-server.ts
│   ├── DependencyInjection/      # Locator + @Locatable
│   ├── Protocols/                # ViewModelType, Coordinator
│   └── Utilities/                # extensions, helpers
└── Resources/
    └── Assets.xcassets           # colors, images
```

(Current state: just `HereApp.swift` + `ContentView.swift` seed. Architecture lands in claude/* feature PRs.)

## Auth model

- **Sign in with Apple** is the primary path on native. Use `AuthenticationServices.framework` directly (no Capacitor plugin).
- After SiwA returns an identity token, exchange via Supabase's `/auth/v1/token?grant_type=id_token` REST endpoint. No Supabase Swift SDK — direct REST calls keep the dep surface minimal.
- Store the access + refresh tokens in Keychain.
- **No magic link on native.** Web keeps it; native doesn't need it once SiwA is reliable.

## Conductor / task system

This repo will use the same conductor pattern as Here-Audio:

- `.claude/CONDUCTOR.md` — coordination doc with open tasks
- `.claude/tasks/NNN-*.md` — self-contained task briefs

A fresh session opening this repo should: read CLAUDE.md (you're here), check `.claude/CONDUCTOR.md` for open tasks, then proceed.

(`.claude/CONDUCTOR.md` lands in the next PR alongside the first architecture scaffolding.)
