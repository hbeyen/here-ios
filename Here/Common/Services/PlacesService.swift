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

  /// Single-row fetch by slug. Same PostgREST path as `list()`, narrowed by
  /// slug; RLS still scopes to rows the signed-in user can read. Used by the
  /// per-place dashboard when entering from a "just created" deep-link (the
  /// `POST /api/places` response carries credentials but not a full Place row).
  func fetch(slug: String) async throws -> Place {
    guard let accessToken = session.accessToken else {
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
      URLQueryItem(name: "slug", value: "eq.\(slug)"),
      URLQueryItem(name: "select", value: "id,slug,name,tagline,accent,is_active"),
      URLQueryItem(name: "limit", value: "1")
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
      let rows = try await api.send(request, expecting: [Place].self)
      guard let place = rows.first else {
        throw APIError.server(status: 404, body: nil)
      }
      return place
    } catch APIError.unauthorized {
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
/// The dashboard reconstructs the Place separately via `PlacesService.fetch`.
///
/// Per the 2026-05-19 architecture decision logged in `.claude/CONDUCTOR.md`,
/// this flat shape is a temporary pragmatic state; the backend task to return
/// `{ place, credentials }` is tracked separately. Until that lands, this
/// type re-uses the `StreamCredentials` nested types so both call sites speak
/// the same vocabulary.
struct CreatePlaceResponse: Decodable, Equatable {
  let slug: String
  let rtmps: StreamCredentials.RTMPS?
  let webRTC: StreamCredentials.WebRTC?
  let playback: StreamCredentials.Playback?

  /// View of the response as a `StreamCredentials`. Lets the dashboard
  /// accept credentials from either the create response or
  /// `StreamCredentialsService.fetch` without caring which produced them.
  var credentials: StreamCredentials {
    StreamCredentials(rtmps: rtmps, webRTC: webRTC, playback: playback)
  }
}
