import SwiftUI

/// Root coordinator. Owns the `SessionService` observation and decides
/// whether to show SignIn or the post-auth flow (Places placeholder for now).
@MainActor
@Observable
final class AppCoordinator: Coordinator {
  var childCoordinators: [any Coordinator] = []

  private let session: SessionService

  init(session: SessionService = Locator.shared.resolve(SessionService.self)) {
    self.session = session
  }

  @ViewBuilder
  func start() -> some View {
    AppRootView(coordinator: self, session: session)
  }

  @ViewBuilder
  func rootView(for state: SessionService.AuthState) -> some View {
    switch state {
    case .unknown:
      SplashView()
    case .signedOut:
      SignInCoordinator(onSignedIn: { [weak self] in
        self?.session.restore()
      }).start()
    case .signedIn(let user):
      PlacesView(user: user, onSignOut: { [weak self] in
        self?.session.signOut()
      })
    }
  }
}

private struct AppRootView: View {
  let coordinator: AppCoordinator
  let session: SessionService

  var body: some View {
    coordinator.rootView(for: session.state)
      .animation(.snappy(duration: 0.25), value: session.state)
  }
}

private struct SplashView: View {
  var body: some View {
    ZStack {
      Color.hereBackground.ignoresSafeArea()
      ProgressView()
        .tint(.white)
    }
  }
}
