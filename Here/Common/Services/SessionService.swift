import Foundation
import Observation

/// Single source of truth for the current authenticated user.
///
/// Holds the Supabase session (access + refresh tokens) and a thin slice of
/// user profile data. Tokens are persisted in Keychain so a relaunch picks
/// up where we left off without re-prompting Face ID.
@MainActor
@Observable
final class SessionService {
  struct CurrentUser: Equatable {
    let id: String
    let email: String?
    let displayName: String?
  }

  enum AuthState: Equatable {
    case unknown          // app just launched, restore in flight
    case signedOut
    case signedIn(CurrentUser)
  }

  private enum KeychainKey {
    static let accessToken = "supabase.access_token"
    static let refreshToken = "supabase.refresh_token"
    static let userId = "supabase.user_id"
    static let email = "supabase.email"
    static let displayName = "supabase.display_name"
  }

  private(set) var state: AuthState = .unknown

  var accessToken: String? {
    Keychain.get(KeychainKey.accessToken)
  }

  var currentUserId: String? {
    if case .signedIn(let user) = state {
      return user.id
    }
    return Keychain.get(KeychainKey.userId)
  }

  init() {
    restore()
  }

  func restore() {
    guard
      let _ = Keychain.get(KeychainKey.accessToken),
      let userId = Keychain.get(KeychainKey.userId)
    else {
      state = .signedOut
      return
    }
    let user = CurrentUser(
      id: userId,
      email: Keychain.get(KeychainKey.email),
      displayName: Keychain.get(KeychainKey.displayName)
    )
    state = .signedIn(user)
  }

  func adopt(session: SupabaseAuthClient.Session, displayName: String?) throws {
    try Keychain.set(session.accessToken, forKey: KeychainKey.accessToken)
    try Keychain.set(session.refreshToken, forKey: KeychainKey.refreshToken)
    if let user = session.user {
      try Keychain.set(user.id, forKey: KeychainKey.userId)
      if let email = user.email {
        try Keychain.set(email, forKey: KeychainKey.email)
      } else {
        Keychain.delete(KeychainKey.email)
      }
    }
    if let displayName, !displayName.isEmpty {
      try Keychain.set(displayName, forKey: KeychainKey.displayName)
    }
    let user = CurrentUser(
      id: session.user?.id ?? Keychain.get(KeychainKey.userId) ?? "",
      email: session.user?.email ?? Keychain.get(KeychainKey.email),
      displayName: displayName ?? Keychain.get(KeychainKey.displayName)
    )
    state = .signedIn(user)
  }

  /// Updates the locally-held display name after a successful Supabase
  /// metadata write. Keeps Keychain + the `signedIn` state in sync so a
  /// relaunch shows the new name without a round-trip.
  func setDisplayName(_ name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty {
      Keychain.delete(KeychainKey.displayName)
    } else {
      try Keychain.set(trimmed, forKey: KeychainKey.displayName)
    }
    guard case .signedIn(let user) = state else { return }
    state = .signedIn(CurrentUser(
      id: user.id,
      email: user.email,
      displayName: trimmed.isEmpty ? nil : trimmed
    ))
  }

  func signOut() {
    Keychain.delete(KeychainKey.accessToken)
    Keychain.delete(KeychainKey.refreshToken)
    Keychain.delete(KeychainKey.userId)
    Keychain.delete(KeychainKey.email)
    Keychain.delete(KeychainKey.displayName)
    state = .signedOut
  }
}
