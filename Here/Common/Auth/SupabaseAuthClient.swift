import Foundation

/// Talks to Supabase Auth REST directly — no SDK. Today we only need the
/// `grant_type=id_token` exchange (Sign in with Apple → Supabase session).
/// Refresh + sign-out land alongside their callers.
final class SupabaseAuthClient {
  // NOTE: no explicit `CodingKeys` with snake_case raw values here. The
  // shared `APIClient.defaultDecoder()` already sets
  // `keyDecodingStrategy = .convertFromSnakeCase`, which converts JSON keys
  // (`access_token`) to camelCase (`accessToken`) BEFORE matching. Adding
  // explicit `case accessToken = "access_token"` makes the decoder look for
  // a key literally named `access_token` in the already-converted keyspace —
  // which no longer exists — so every field fails as `keyNotFound`, surfacing
  // as "data couldn't be read because it is missing". Let the strategy do it.
  struct Session: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let tokenType: String?
    let user: User?
  }

  struct User: Decodable {
    let id: String
    let email: String?
    let userMetadata: [String: AnyJSON]?

    /// Broadcaster-facing name, if one was set. Supabase stores it under
    /// `full_name` (what `updateUser({ data: { full_name } })` writes) or, on
    /// the very first Apple auth, `name`. Falls back to nil so callers keep
    /// showing the email.
    var displayName: String? {
      for key in ["full_name", "name"] {
        if let value = userMetadata?[key]?.stringValue, !value.isEmpty {
          return value
        }
      }
      return nil
    }
  }

  private let environment: AppEnvironment
  private let api: APIClient

  init(environment: AppEnvironment, api: APIClient) {
    self.environment = environment
    self.api = api
  }

  func signInWithApple(idToken: String, nonce: String) async throws -> Session {
    guard var components = URLComponents(url: environment.supabaseURL, resolvingAgainstBaseURL: false) else {
      throw APIError.invalidURL
    }
    components.path = "/auth/v1/token"
    components.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
    guard let url = components.url else {
      throw APIError.invalidURL
    }

    let payload = SignInPayload(provider: "apple", idToken: idToken, nonce: nonce)
    let body = try api.encode(payload)
    let request = api.makeRequest(
      url: url,
      method: .post,
      headers: [
        "apikey": environment.supabaseAnonKey,
        "Authorization": "Bearer \(environment.supabaseAnonKey)"
      ],
      body: body
    )
    return try await api.send(request, expecting: Session.self)
  }

  /// Persists a broadcaster-chosen display name to Supabase `user_metadata`.
  /// REST equivalent of `supabase.auth.updateUser({ data: { full_name } })`:
  /// PATCH `/auth/v1/user` with `{ "data": { "full_name": "<name>" } }`.
  /// Needed because Apple only returns the name on the *first* auth, so a
  /// user who deleted + reinstalled (or signed in on a second device) is left
  /// with just the private-relay email until they set a name here.
  func updateDisplayName(_ name: String, accessToken: String) async throws -> User {
    guard var components = URLComponents(url: environment.supabaseURL, resolvingAgainstBaseURL: false) else {
      throw APIError.invalidURL
    }
    components.path = "/auth/v1/user"
    guard let url = components.url else {
      throw APIError.invalidURL
    }

    let payload = UpdateUserPayload(data: .init(fullName: name))
    let body = try api.encode(payload)
    let request = api.makeRequest(
      url: url,
      method: .put,
      headers: [
        "apikey": environment.supabaseAnonKey,
        "Authorization": "Bearer \(accessToken)"
      ],
      body: body
    )
    return try await api.send(request, expecting: User.self)
  }

  // No explicit snake_case `CodingKeys` here. `APIClient.defaultEncoder()`
  // sets `keyEncodingStrategy = .convertToSnakeCase`, so `fullName` already
  // serializes as `full_name`. Adding `case fullName = "full_name"` would
  // make the encoder convert the *already*-snake_cased key again — the mirror
  // image of the decode-side double-conversion bug logged in CONDUCTOR.md.
  private struct UpdateUserPayload: Encodable {
    let data: Metadata

    struct Metadata: Encodable {
      let fullName: String
    }
  }

  private struct SignInPayload: Encodable {
    let provider: String
    let idToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
      case provider
      case idToken = "id_token"
      case nonce
    }
  }
}

/// Tiny `Codable` wrapper for arbitrary JSON (used for `user_metadata` whose
/// shape we don't pin). Decoding-only — we never serialize back.
enum AnyJSON: Decodable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case array([AnyJSON])
  case object([String: AnyJSON])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([AnyJSON].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: AnyJSON].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }
  }

  var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }
}
