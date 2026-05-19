# Task 002: GitHub Actions CI for here-ios

**Status**: OPEN
**Owner**: Fresh Claude Code session (or conductor inline — small)
**Created**: 2026-05-18

## Goal

Wire a GitHub Actions workflow that runs `xcodegen generate` + `xcodebuild build` on every push and PR. Catches Swift compile regressions before they hit main. No tests yet — just compile-clean.

## Context

PR #1 had no CI gate because the repo was fresh. We need one before more PRs land, otherwise broken builds reach main silently.

Build invocation (already verified working locally):

```bash
xcodegen generate
xcodebuild -project Here.xcodeproj -scheme Here -configuration Debug -destination "generic/platform=iOS Simulator" build
```

GitHub Actions provides `macos-15` (or `macos-14`) runners with Xcode pre-installed. `xcodegen` needs `brew install xcodegen` as a step.

## Steps

1. Create `.github/workflows/ci.yml`:
   - Triggers: push to main, push to `claude/*`, pull_request
   - Job `build` on `macos-15`
   - Steps:
     - `actions/checkout@v4`
     - `brew install xcodegen` (or use a marketplace action that installs it)
     - `xcodegen generate`
     - `xcodebuild -project Here.xcodeproj -scheme Here -configuration Debug -destination "generic/platform=iOS Simulator" build`
   - Cache derived data + brew deps if it speeds things up (optional)

2. Verify the workflow runs green on a test push.

3. Add a CI badge to README.md.

## Acceptance

- Push to a `claude/*` branch triggers the workflow
- Workflow completes green (BUILD SUCCEEDED)
- README shows the badge

## Out of scope

- Tests (no test target yet)
- TestFlight upload (separate task — Fastlane)
- Code coverage
- SwiftLint / SwiftFormat enforcement (defer to a polish task)
- macOS / Linux runners (iOS-only)

## How to report back

PR URL, workflow URL on a successful run, any judgment calls.
