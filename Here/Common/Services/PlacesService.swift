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

  /// Edits an existing place's metadata (name / tagline / accent). Slug and
  /// geofence are out of scope — slug is the row identity, geofence editing is
  /// a separate MapKit task.
  ///
  /// Goes direct to PostgREST PATCH (not the worker): renaming touches no
  /// external resource, and the `places_owner_update` RLS policy scopes the
  /// write to the signed-in owner. `Prefer: return=representation` makes
  /// PostgREST echo the updated row so we can reflect it immediately.
  func update(
    slug: String,
    name: String,
    tagline: String,
    accent: String
  ) async throws -> Place {
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
      URLQueryItem(name: "select", value: "id,slug,name,tagline,accent,is_active")
    ]
    guard let url = components.url else {
      throw APIError.invalidURL
    }

    let body = UpdatePlaceRequest(name: name, tagline: tagline, accent: accent)
    let request = api.makeRequest(
      url: url,
      method: .patch,
      headers: [
        "apikey": environment.supabaseAnonKey,
        "Authorization": "Bearer \(accessToken)",
        "Prefer": "return=representation"
      ],
      body: try api.encode(body)
    )

    do {
      let rows = try await api.send(request, expecting: [Place].self)
      guard let place = rows.first else {
        // 200 with an empty array means RLS matched no row the user can write.
        throw APIError.server(status: 404, body: nil)
      }
      return place
    } catch APIError.unauthorized {
      session.signOut()
      throw APIError.unauthorized
    }
  }

  /// Deletes a place. Goes through the worker (`DELETE /api/places?slug=…`)
  /// rather than PostgREST: the worker also tears down the Cloudflare Stream
  /// Live Input so it isn't orphaned. The worker is owner-scoped server-side
  /// (403 if the slug isn't yours).
  func delete(slug: String) async throws {
    guard let accessToken = session.accessToken else {
      throw APIError.unauthorized
    }

    var components = URLComponents()
    components.queryItems = [URLQueryItem(name: "slug", value: slug)]
    let base = environment.workerBaseURL.appendingPathComponent("api/places")
    guard let query = components.percentEncodedQuery,
          let url = URL(string: "\(base.absoluteString)?\(query)") else {
      throw APIError.invalidURL
    }

    let request = api.makeRequest(
      url: url,
      method: .delete,
      headers: ["Authorization": "Bearer \(accessToken)"]
    )

    do {
      try await api.send(request)
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

/// Body for the PostgREST PATCH. All three columns are single-word, so the
/// encoder's `convertToSnakeCase` is a no-op here — the JSON keys match the
/// `places` column names verbatim.
private struct UpdatePlaceRequest: Encodable {
  let name: String
  let tagline: String
  let accent: String
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
