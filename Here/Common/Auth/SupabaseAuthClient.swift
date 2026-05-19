import Foundation

/// Talks to Supabase Auth REST directly — no SDK. Today we only need the
/// `grant_type=id_token` exchange (Sign in with Apple → Supabase session).
/// Refresh + sign-out land alongside their callers.
final class SupabaseAuthClient {
  struct Session: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let tokenType: String?
    let user: User?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case expiresIn = "expires_in"
      case tokenType = "token_type"
      case user
    }
  }

  struct User: Decodable {
    let id: String
    let email: String?
    let userMetadata: [String: AnyJSON]?

    enum CodingKeys: String, CodingKey {
      case id
      case email
      case userMetadata = "user_metadata"
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
