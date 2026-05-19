import Foundation

/// Cloudflare Stream Live-Input credentials for a place.
///
/// Returned by the HERE worker at `GET /api/places/{slug}/stream` and
/// echoed in the body of `POST /api/places` after a successful create.
/// Source of truth for the JSON shape: `Here-Audio/lib/cloudflare-stream.ts`
/// (`LiveInput` type) — the worker just passes it through verbatim.
///
/// All sub-fields are optional because dev / stubbed responses may omit
/// individual URLs; the dashboard surfaces them with copy/fallback UI
/// rather than crashing on missing values.
struct StreamCredentials: Decodable, Equatable {
  let rtmps: RTMPS?
  let webRTC: WebRTC?
  let playback: Playback?

  struct RTMPS: Decodable, Equatable {
    let url: String?
    let streamKey: String?
  }

  struct WebRTC: Decodable, Equatable {
    let url: String?
  }

  struct Playback: Decodable, Equatable {
    let hls: String?
    let dash: String?
  }
}
