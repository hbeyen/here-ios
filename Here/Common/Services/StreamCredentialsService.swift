import Foundation

/// Fetches Cloudflare Stream Live-Input credentials for one of the signed-in
/// user's places.
///
/// Reads go through the HERE worker (`GET /api/places/{slug}/stream`), not
/// PostgREST — the stream key never lands in Supabase; the worker calls the
/// Cloudflare Stream API server-side and proxies the response. The endpoint
/// is owner-scoped on the server (403 if the slug isn't yours), so the iOS
/// client only needs to forward the Supabase access token as a Bearer.
@MainActor
final class StreamCredentialsService {
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

  func fetch(slug: String) async throws -> StreamCredentials {
    guard let accessToken = session.accessToken else {
      throw APIError.unauthorized
    }

    let url = environment.workerBaseURL
      .appendingPathComponent("api/places")
      .appendingPathComponent(slug)
      .appendingPathComponent("stream")

    let request = api.makeRequest(
      url: url,
      method: .get,
      headers: ["Authorization": "Bearer \(accessToken)"]
    )

    do {
      return try await api.send(request, expecting: StreamCredentials.self)
    } catch APIError.unauthorized {
      session.signOut()
      throw APIError.unauthorized
    }
  }
}
