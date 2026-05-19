import Foundation
import Security

/// Minimal Keychain wrapper. Stores small string values (auth tokens) under
/// the app's default service. Kept dependency-free on purpose — Supabase
/// REST integration doesn't need a full Keychain abstraction yet.
enum Keychain {
  enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case dataConversion
  }

  static let service = "fm.here.app.auth"

  static func set(_ value: String, forKey key: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw KeychainError.dataConversion
    }
    let baseQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]
    let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    switch updateStatus {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var addQuery = baseQuery
      addQuery.merge(attributes) { _, new in new }
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw KeychainError.unexpectedStatus(addStatus)
      }
    default:
      throw KeychainError.unexpectedStatus(updateStatus)
    }
  }

  static func get(_ key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else {
      return nil
    }
    return value
  }

  static func delete(_ key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    SecItemDelete(query as CFDictionary)
  }
}
