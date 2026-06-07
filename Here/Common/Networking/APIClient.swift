import Foundation

/// Thin URLSession + Codable wrapper used for talking to the HERE worker
/// (`https://here-audio.henock-23c.workers.dev/api/*`) and to Supabase REST
/// (`https://xiqyaryjagujgsxcuabb.supabase.co/...`).
///
/// Kept intentionally small — no interceptor pipeline, no plugin system,
/// no retry. When auth headers or refresh logic are needed, callers build
/// the request and pass it in.
final class APIClient {
  enum Method: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
  }

  private let session: URLSession
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(
    session: URLSession = .shared,
    encoder: JSONEncoder = APIClient.defaultEncoder(),
    decoder: JSONDecoder = APIClient.defaultDecoder()
  ) {
    self.session = session
    self.encoder = encoder
    self.decoder = decoder
  }

  func send<Response: Decodable>(
    _ request: URLRequest,
    expecting: Response.Type
  ) async throws -> Response {
    let (data, http) = try await perform(request)
    if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
      return empty
    }
    do {
      return try decoder.decode(Response.self, from: data)
    } catch {
      // 2xx responses can still carry an error envelope (Supabase
      // occasionally returns 200 with `{ error, error_description }` when
      // an upstream provider rejected the request). Try the envelope parse
      // first; fall back to surfacing the raw body alongside the decode
      // error so a human can see what came back.
      if let parsed = APIClient.parseErrorMessage(from: data) {
        throw APIError.serverMessage(status: http.statusCode, message: parsed, body: bodyPreview(from: data))
      }
      throw APIError.decoding(error, body: bodyPreview(from: data))
    }
  }

  func send(_ request: URLRequest) async throws {
    _ = try await perform(request)
  }

  func makeRequest(
    url: URL,
    method: Method = .get,
    headers: [String: String] = [:],
    body: Data? = nil
  ) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    if let body {
      request.httpBody = body
      if request.value(forHTTPHeaderField: "Content-Type") == nil {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      }
    }
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  func encode<T: Encodable>(_ value: T) throws -> Data {
    do {
      return try encoder.encode(value)
    } catch {
      throw APIError.decoding(error)
    }
  }

  private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw APIError.transport(error)
    }
    guard let http = response as? HTTPURLResponse else {
      throw APIError.server(status: -1, body: nil)
    }
    switch http.statusCode {
    case 200..<300:
      return (data, http)
    case 401, 403:
      // Try to surface the parsed message too — Supabase tells us things
      // like "No API key found in request" via the `message` field, which
      // is much more useful than a bare "Session expired".
      if let parsed = APIClient.parseErrorMessage(from: data) {
        throw APIError.serverMessage(status: http.statusCode, message: parsed, body: bodyPreview(from: data))
      }
      throw APIError.unauthorized
    default:
      if let parsed = APIClient.parseErrorMessage(from: data) {
        throw APIError.serverMessage(status: http.statusCode, message: parsed, body: bodyPreview(from: data))
      }
      throw APIError.server(status: http.statusCode, body: bodyPreview(from: data))
    }
  }

  /// Attempts to pull a human-readable message out of an error response body.
  /// Tries the shapes Supabase + the worker actually return today:
  ///
  /// - `{"code": 400, "error_code": "validation_failed", "msg": "..."}`         (gotrue v2)
  /// - `{"error": "invalid request", "error_description": "..."}`               (gotrue OAuth-style)
  /// - `{"message": "...", "hint": "..."}`                                       (Supabase gateway / PostgREST)
  /// - `{"error": "..."}`                                                        (plain)
  ///
  /// Falls back to nil if the body isn't JSON or doesn't contain anything
  /// we recognise; callers should then surface the raw body instead.
  static func parseErrorMessage(from data: Data) -> String? {
    guard !data.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    let candidates: [String?] = [
      json["error_description"] as? String,
      json["msg"] as? String,
      json["message"] as? String,
      json["error"] as? String,
      json["hint"] as? String,
      (json["error_code"] as? String).map { "\($0)" }
    ]
    let first = candidates.compactMap { $0 }.first { !$0.isEmpty }
    return first
  }

  /// First ~200 chars of the body for logging/diagnostic purposes.
  private func bodyPreview(from data: Data) -> String? {
    guard let body = String(data: data, encoding: .utf8), !body.isEmpty else {
      return nil
    }
    let limit = 200
    if body.count <= limit {
      return body
    }
    return String(body.prefix(limit)) + "…"
  }

  static func defaultEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }

  static func defaultDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }
}

/// Marker for endpoints that return no body (or whose body we ignore).
struct EmptyResponse: Decodable {}
