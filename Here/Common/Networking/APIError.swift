import Foundation

enum APIError: Error, LocalizedError {
  case invalidURL
  case transport(Error)
  case server(status: Int, body: String?)
  /// A 4xx/5xx response where we managed to decode a meaningful message out
  /// of the body. Carries the parsed message plus the original status + raw
  /// body so callers can log/diagnose if needed.
  case serverMessage(status: Int, message: String, body: String?)
  case decoding(Error, body: String? = nil)
  case unauthorized

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid URL."
    case .transport(let error):
      return "Network error: \(error.localizedDescription)"
    case .server(let status, let body):
      if let body, !body.isEmpty {
        return "Server error (\(status)): \(body)"
      }
      return "Server error (\(status))."
    case .serverMessage(let status, let message, _):
      return "HTTP \(status): \(message)"
    case .decoding(let error, let body):
      if let body, !body.isEmpty {
        return "Could not parse response (\(error.localizedDescription)). Body: \(body)"
      }
      return "Could not parse response: \(error.localizedDescription)"
    case .unauthorized:
      return "Session expired. Please sign in again."
    }
  }
}
