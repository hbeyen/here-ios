import CoreLocation
import Foundation

/// Fetches the signed-in user's owned places and creates new ones.
///
/// READS hit Supabase PostgREST directly (`/rest/v1/places`); the HERE worker
/// (`/api/places`) doesn't yet expose GET, and `app/broadcaster/page.tsx` on
/// web reads server-side via Supabase too. RLS would refuse a SELECT for any
/// other user's rows even if our `owner_id=eq.…` filter were stripped. When a
/// GET endpoint lands on the worker we can swap the URL with no other changes
/// to the call site.
///
/// WRITES go through the worker, which provisions a Cloudflare Stream Live
/// Input and enforces tier caps before inserting the row.
@MainActor
final class PlacesService {
  private let api: APIClient
  private let environment: AppEnvironment
  private let session: SessionService

  init(
    api: APIClient,
    environment: AppEnvironment,
    session: SessionService
  ) {
    self.api = api
    self.environment = environment
    self.session = session
  }

  func list() async throws -> [Place] {
    guard let accessToken = session.accessToken else {
      throw APIError.unauthorized
    }
    guard let userId = session.currentUserId else {
      throw APIError.unauthorized
    }

    guard var components = URLComponents(
      url: environment.supabaseURL,
      resolvingAgainstBaseURL: false
    ) else {
      throw APIError.invalidURL
    }
    components.path = "/rest/v1/places"
    components.queryItems = [
      URLQueryItem(name: "owner_id", value: "eq.\(userId)"),
      URLQueryItem(name: "select", value: "id,slug,name,tagline,accent,is_active"),
      URLQueryItem(name: "order", value: "created_at.desc")
    ]
    guard let url = components.url else {
      throw APIError.invalidURL
    }

    let request = api.makeRequest(
      url: url,
      method: .get,
      headers: [
        "apikey": environment.supabaseAnonKey,
        "Authorization": "Bearer \(accessToken)"
      ]
    )

    do {
      return try await api.send(request, expecting: [Place].self)
    } catch APIError.unauthorized {
      // Access token is no longer valid. Refresh-token rotation is out of
      // scope for task 001; clear the session so the user lands back on /sign-in.
      session.signOut()
      throw APIError.unauthorized
    }
  }

  func create(
    name: String,
    slug: String,
    tagline: String?,
    accent: String,
    center: CLLocationCoordinate2D,
    geofence: GeoJSONPolygon
  ) async throws -> CreatePlaceResponse {
    guard let accessToken = session.accessToken else {
      throw APIError.unauthorized
    }

    let url = environment.workerBaseURL.appendingPathComponent("api/places")

    let body = CreatePlaceRequest(
      slug: slug,
      name: name,
      tagline: tagline ?? "",
      accent: accent,
      center: .init(lat: center.latitude, lng: center.longitude),
      geofence: geofence
    )

    let request = api.makeRequest(
      url: url,
      method: .post,
      headers: ["Authorization": "Bearer \(accessToken)"],
      body: try api.encode(body)
    )

    do {
      return try await api.send(request, expecting: CreatePlaceResponse.self)
    } catch APIError.unauthorized {
      session.signOut()
      throw APIError.unauthorized
    }
  }
}

/// Body for `POST /api/places`. Mirrors the `Body` type in
/// `Here-Audio/app/api/places/route.ts`. `keyEncodingStrategy =
/// .convertToSnakeCase` would only affect single-word keys here, but we
/// rely on the worker's snake-case-tolerant validator — it reads `center`
/// and `geofence` verbatim, so this stays plain camelCase.
private struct CreatePlaceRequest: Encodable {
  let slug: String
  let name: String
  let tagline: String
  let accent: String
  let center: Center
  let geofence: GeoJSONPolygon

  struct Center: Encodable {
    let lat: Double
    let lng: Double
  }
}

/// Response from `POST /api/places`. The worker returns the slug plus
/// freshly-minted Cloudflare Stream credentials — NOT a full Place row.
/// Task 004 (per-place dashboard) will lean on `rtmps` + `playback` to show
/// the broadcaster their ingest URL and to play back their own stream.
struct CreatePlaceResponse: Decodable, Equatable {
  let slug: String
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
