# Here-iOS

[![CI](https://github.com/hbeyen/here-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/hbeyen/here-ios/actions/workflows/ci.yml)

Native SwiftUI iOS broadcaster app for [HERE](https://github.com/hbeyen/Here-Audio) — the geofenced live-audio platform. Listeners stay on the web; broadcasters get this native app for proper iOS UX + ReplayKit system-audio capture.

**Status**: v0.3 in development. The Capacitor wrapper currently shipping in `Here-Audio/ios/` is the v0.2 broadcaster experience and will be retired once this app reaches feature parity.

## Setup

```bash
# Prereqs: macOS, Xcode 16+, homebrew, xcodegen
brew install xcodegen        # if not already
git clone https://github.com/hbeyen/here-ios.git
cd here-ios
xcodegen generate            # produces Here.xcodeproj from project.yml
open Here.xcodeproj
```

See [CLAUDE.md](CLAUDE.md) for the working conventions, architecture, and references.
