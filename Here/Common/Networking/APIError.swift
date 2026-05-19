import Foundation

enum APIError: Error, LocalizedError {
  case invalidURL
  case transport(Error)
  case server(status: Int, body: String?)
  case decoding(Error)
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
    case .decoding(let error):
      return "Could not parse response: \(error.localizedDescription)"
    case .unauthorized:
      return "Session expired. Please sign in again."
    }
  }
}
