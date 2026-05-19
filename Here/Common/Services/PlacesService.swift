import Foundation

/// Fetches the signed-in user's owned places.
///
/// The HERE worker (`/api/places`) currently exposes POST + DELETE but no
/// list endpoint — `app/broadcaster/page.tsx` reads owned places server-side
/// via a direct Supabase query. We mirror that here by hitting Supabase
/// PostgREST directly (`/rest/v1/places`); RLS would refuse a SELECT for any
/// other user's rows even if our `owner_id=eq.…` filter were stripped. When
/// a GET endpoint lands on the worker we can swap the URL with no other
/// changes to the call site.
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
}
