import SwiftUI

@main
struct HereApp: App {
  @State private var coordinator: AppCoordinator

  init() {
    Locator.shared.registerAppDependencies()
    _coordinator = State(initialValue: AppCoordinator())
  }

  var body: some Scene {
    WindowGroup {
      coordinator.start()
    }
  }
}

extension Color {
  static let hereBackground = Color(red: 5/255, green: 5/255, blue: 5/255)
}
