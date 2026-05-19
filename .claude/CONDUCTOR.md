# Here-iOS Conductor

This file is the coordination doc for the native iOS app. The **conductor** is whatever Claude Code session is currently driving open work — it dispatches subagents (or hands briefs to fresh sessions) and tracks status here. A new session opening this repo should be able to pick up cold from this file alone.

If you're a fresh session: read this top to bottom, then read [`CLAUDE.md`](../CLAUDE.md) for code conventions. Architecture decision lives in [hbeyen/Here-Audio/ROADMAP.md](https://github.com/hbeyen/Here-Audio/blob/main/ROADMAP.md) — web for listeners, native for broadcasters.

## Active goals (v0.3 — 2026-Q3)

- **Feature parity** with the retired Capacitor broadcaster surface: sign in, places list, create place, per-place dashboard, settings, sign out.
- **ReplayKit broadcast extension** ported from `Here-Audio/ios/App/BroadcastUpload/` once the rest of the flow is solid.
- **TestFlight distribution** via Fastlane, replacing the Capacitor build that currently sits in TestFlight under the same bundle ID `fm.here.app`.

## Open tasks

| ID  | Status | Owner | Title |
| --- | ------ | ----- | ----- |
| 001 | DONE | Fresh Claude Code session | [SignIn → Places list end-to-end](tasks/001-signin-to-places-end-to-end.md) — merged as PR #3 (`26075b0`). Decisions logged below. |
| 002 | OPEN | Conductor inline OR fresh session | [GitHub Actions CI for here-ios](tasks/002-github-actions-ci.md) |
| 003 | OPEN | Fresh Claude Code session | [Create new place flow](tasks/003-create-new-place.md) |
| 004 | OPEN | Fresh Claude Code session | [Per-place dashboard](tasks/004-place-dashboard.md) |

## Status legend

- **OPEN** — ready to start; brief is up to date.
- **DISPATCHED** — a subagent / external session is in flight; don't duplicate.
- **BLOCKED** — waiting on something external (dashboard click, decision, dep upgrade).
- **DONE** — close out by deleting the brief or moving it to `tasks/done/`.

## Recent decisions log

- **2026-05-18** — Repo created (commit `3f38ab8`). SwiftUI app scaffold + xcodegen project spec (`469267f`). PR #1 architecture: Coordinator + Locator + Networking + SignIn scene with native SiwA, 22 Swift files + 4 resources (`fe1da51`).
- **2026-05-18** — Architecture lifted (read-only) from `~/Desktop/GitHub/Says/Says-iOS/`. Diverges where modern Swift suggests (two-space indent, `@Observable` macro, `async`/`await` over Combine where natural, `@MainActor` for Swift 6 isolation).
- **2026-05-18** — Bundle ID `fm.here.app` reused from the retired Capacitor wrapper. Team Says, Inc. (`7594TCUA42`). iOS 17+ minimum.
- **2026-05-18** — Supabase anon key wiring deferred to task 001 (slot exists in code as `HERE_SUPABASE_ANON_KEY` Info.plist key; value gets added via project.yml in task 001's PR — anon key is the public `NEXT_PUBLIC_SUPABASE_ANON_KEY` from Here-Audio, safe to commit).
- **2026-05-19** — Task 001 merged as PR #3 (`26075b0`). Three concrete decisions worth remembering:
  1. **READ paths bypass the Cloudflare worker.** `PlacesService.list()` queries Supabase PostgREST directly (`/rest/v1/places?owner_id=eq.…`) using the anon JWT + an `Authorization: Bearer <access_token>` header. RLS enforces owner scoping. Reason: `GET /api/places` doesn't exist on the worker — only POST/DELETE. The web broadcaster index does the same. If a worker GET ever lands, swap the URL in `PlacesService.list()` and drop the apikey header.
  2. **WRITE paths still go through the worker.** Create/update/delete touch external resources (Cloudflare Stream Live Input provisioning) so they live in the worker. Task 003 (create place) POSTs to `/api/places`.
  3. **Info.plist is xcodegen-managed via `targets.Here.info.properties`**, NOT `GENERATE_INFOPLIST_FILE: YES + INFOPLIST_KEY_*`. Xcode silently drops custom keys whose suffix isn't in Apple's known-key allowlist (`HERE_SUPABASE_ANON_KEY` is one such). Future custom plist keys go in `project.yml`'s `info.properties` block. `Here/Resources/Info.plist` is committed.

## How to dispatch a task

**Inline (subagent within the conductor chat)**:
```
Agent({
  description: "Short description",
  subagent_type: "general-purpose",
  prompt: <paste full brief>
})
```

**Fresh CLI session (external)**:
- Conductor produces a self-contained handoff prompt that references this repo's path + the task brief
- User pastes into a new `claude` session opened at `~/Developer/here-ios`
- Fresh session reads CLAUDE.md (auto-loaded), executes, reports back
- User pastes the report into the conductor chat
- Conductor updates this CONDUCTOR.md + dispatches the next task

## Reference repos

- `~/Desktop/GitHub/Says/Says-iOS/` — Henock's prior iOS app, architecture template. **READ-ONLY** — see CLAUDE.md for the rule.
- `~/Developer/Here-Audio/` — companion Next.js + Cloudflare backend. Read-only context for endpoint shapes; never write into it from this repo's work.
