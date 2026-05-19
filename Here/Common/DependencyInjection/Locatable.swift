import Foundation

/// `@Locatable var thing: SomeService` → lazy resolution from `Locator.shared`
/// on first access. Default mode is `.sharedInstance` (cached singleton).
///
/// Use `@Locatable(.newInstance) var thing: SomeService` for a fresh instance
/// on every access (rare — most services should be shared).
@propertyWrapper
final class Locatable<Dependency> {
  private let mode: LocatingMode

  init(_ mode: LocatingMode = .sharedInstance) {
    self.mode = mode
  }

  var wrappedValue: Dependency {
    Locator.shared.resolve(Dependency.self, mode: mode)
  }
}
