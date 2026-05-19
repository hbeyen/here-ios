import SwiftUI

@MainActor
final class SignInCoordinator: Coordinator {
  var childCoordinators: [any Coordinator] = []

  private let onSignedIn: () -> Void

  init(onSignedIn: @escaping () -> Void) {
    self.onSignedIn = onSignedIn
  }

  @ViewBuilder
  func start() -> some View {
    SignInView(viewModel: SignInViewModel(onSignedIn: onSignedIn))
  }
}
