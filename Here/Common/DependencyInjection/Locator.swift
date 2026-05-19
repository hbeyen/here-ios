import Foundation

enum LocatingMode {
  case newInstance
  case sharedInstance
}

/// Lightweight service locator. Single global, lazy resolution, optional caching.
///
/// Pattern lifted from Says-iOS (`Says/Common/Dependency Injection/Locator.swift`)
/// and re-typed for here-ios. Registration happens at app launch from
/// `Locator+Dependencies.swift`; resolution happens via `@Locatable` or
/// `Locator.shared.resolve(...)` directly.
final class Locator {
  typealias Resolver = () -> Any

  static let shared = Locator()

  private var resolvers: [String: Resolver] = [:]
  private var cache: [String: Any] = [:]

  private init() {}

  func register<T, R>(_ type: T.Type, service: @escaping () -> R) {
    let key = String(reflecting: type)
    resolvers[key] = service
  }

  /// Clears cached shared instances. Useful on sign-out so per-user state
  /// (session, anything keyed off the user id) is reconstructed fresh.
  func clearCache() {
    cache.removeAll()
  }

  func resolve<T>(_ type: T.Type, mode: LocatingMode = .sharedInstance) -> T {
    let key = String(reflecting: type)

    if mode == .sharedInstance, let cached = cache[key] as? T {
      return cached
    }

    guard let resolver = resolvers[key], let service = resolver() as? T else {
      fatalError("Locator: \(key) has not been registered.")
    }

    if mode == .sharedInstance {
      cache[key] = service
    }

    return service
  }
}
