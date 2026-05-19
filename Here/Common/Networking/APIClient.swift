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
    let (data, _) = try await perform(request)
    if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
      return empty
    }
    do {
      return try decoder.decode(Response.self, from: data)
    } catch {
      throw APIError.decoding(error)
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
      throw APIError.unauthorized
    default:
      let body = String(data: data, encoding: .utf8)
      throw APIError.server(status: http.statusCode, body: body)
    }
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
