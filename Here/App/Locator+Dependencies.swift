import Foundation

extension Locator {
  /// Register every globally-shared service. Called once at app launch from
  /// `HereApp.init()`. Keeping the registration list in one file means a
  /// new service is one edit, not a hunt-and-peck.
  func registerAppDependencies(environment: AppEnvironment = .production) {
    register(AppEnvironment.self) { environment }

    register(APIClient.self) { APIClient() }

    register(SupabaseAuthClient.self) {
      SupabaseAuthClient(
        environment: Locator.shared.resolve(AppEnvironment.self),
        api: Locator.shared.resolve(APIClient.self)
      )
    }

    register(SessionService.self) {
      MainActor.assumeIsolated {
        SessionService()
      }
    }

    register(PlacesService.self) {
      MainActor.assumeIsolated {
        PlacesService(
          api: Locator.shared.resolve(APIClient.self),
          environment: Locator.shared.resolve(AppEnvironment.self),
          session: Locator.shared.resolve(SessionService.self)
        )
      }
    }

    register(StreamCredentialsService.self) {
      MainActor.assumeIsolated {
        StreamCredentialsService(
          api: Locator.shared.resolve(APIClient.self),
          environment: Locator.shared.resolve(AppEnvironment.self),
          session: Locator.shared.resolve(SessionService.self)
        )
      }
    }
  }
}
