import SwiftUI

/// Minimal coordinator contract. A coordinator owns a slice of navigation,
/// holds its child coordinators, and exposes a SwiftUI `start()` view that
/// the parent embeds.
///
/// Says-iOS uses a UIKit-flavoured coordinator (push/present on a
/// `UINavigationController`). Here-iOS is SwiftUI-first, so `start()` returns
/// a `View` and parent coordinators compose children declaratively (via
/// `NavigationStack`, `.sheet`, or just direct embedding).
@MainActor
protocol Coordinator: AnyObject {
  associatedtype Body: View

  var childCoordinators: [any Coordinator] { get set }

  @ViewBuilder func start() -> Body
}

extension Coordinator {
  func release(_ coordinator: any Coordinator) {
    childCoordinators.removeAll { $0 === coordinator }
  }
}
