import Foundation
import Observation

@MainActor
@Observable
final class PlacesViewModel: ViewModelType {
  struct Input {
    let load: @MainActor () async -> Void
    let refresh: @MainActor () async -> Void
  }

  struct Output {
    var places: [Place]
    var status: Status
    var errorMessage: String?
  }

  enum Status: Equatable {
    case loading
    case loaded
    case empty
    case failed
  }

  private(set) var output = Output(places: [], status: .loading, errorMessage: nil)

  var input: Input {
    Input(
      load: { [weak self] in await self?.load() },
      refresh: { [weak self] in await self?.refresh() }
    )
  }

  @ObservationIgnored @Locatable private var service: PlacesService

  func load() async {
    if output.places.isEmpty {
      output.status = .loading
    }
    await fetch()
  }

  func refresh() async {
    // Pull-to-refresh — leave the existing list visible while reloading.
    await fetch()
  }

  private func fetch() async {
    output.errorMessage = nil
    do {
      let places = try await service.list()
      output.places = places
      output.status = places.isEmpty ? .empty : .loaded
    } catch APIError.unauthorized {
      // PlacesService already cleared the session; AppCoordinator will route
      // back to /sign-in via the @Observable state change. No need to surface
      // an error banner here.
      output.status = .failed
    } catch {
      output.status = .failed
      output.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }
}
