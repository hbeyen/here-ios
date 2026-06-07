import Foundation
import Observation
import UIKit

/// Drives the per-place dashboard. Holds both the `Place` row (cheap, from
/// PostgREST) and `StreamCredentials` (sensitive, from the worker), each of
/// which can be `nil` while loading.
///
/// The two-init story matters: from the Places list we already have a Place
/// in hand and only need to fetch credentials; from a "just created"
/// deep-link we have credentials in hand and need to fetch the Place.
/// Either entry should land on a usable screen with no avoidable spinners.
@MainActor
@Observable
final class PlaceDashboardViewModel: ViewModelType {
  struct Input {
    let load: @MainActor () async -> Void
    let refresh: @MainActor () async -> Void
    let toggleStreamKey: @MainActor () -> Void
    let copy: @MainActor (String, String) -> Void
    let applyEdit: @MainActor (Place) -> Void
    let delete: @MainActor () async -> Bool
  }

  struct Output {
    var place: Place?
    var credentials: StreamCredentials?
    var isLoadingPlace: Bool
    var isLoadingCredentials: Bool
    var errorMessage: String?
    var streamKeyRevealed: Bool
    var isDeleting: Bool
    /// Short-lived toast: e.g. "RTMPS URL copied". `nil` when no toast is
    /// being shown. The view watches this and clears it on a timer.
    var copyToast: String?
  }

  private(set) var output: Output

  private let slug: String
  @ObservationIgnored @Locatable private var placesService: PlacesService
  @ObservationIgnored @Locatable private var credentialsService: StreamCredentialsService

  /// `place` is what the list-tap entry passes; `prefetchedCredentials` is
  /// what the just-created deep-link passes. Either or both may be supplied.
  /// `slug` falls back to `place?.slug`; the deep-link path supplies it
  /// directly so we can fetch the Place by slug.
  init(
    slug: String,
    place: Place? = nil,
    prefetchedCredentials: StreamCredentials? = nil
  ) {
    self.slug = slug
    self.output = Output(
      place: place,
      credentials: prefetchedCredentials,
      isLoadingPlace: place == nil,
      isLoadingCredentials: prefetchedCredentials == nil,
      errorMessage: nil,
      streamKeyRevealed: false,
      isDeleting: false,
      copyToast: nil
    )
  }

  var input: Input {
    Input(
      load: { [weak self] in await self?.load() },
      refresh: { [weak self] in await self?.refresh() },
      toggleStreamKey: { [weak self] in self?.toggleStreamKey() },
      copy: { [weak self] value, label in self?.copy(value: value, label: label) },
      applyEdit: { [weak self] place in self?.applyEdit(place) },
      delete: { [weak self] in await self?.delete() ?? false }
    )
  }

  /// Initial load — fetches only what's missing. Idempotent; safe to call
  /// from `.task` on every appearance.
  func load() async {
    let needsPlace = output.place == nil
    let needsCredentials = output.credentials == nil
    guard needsPlace || needsCredentials else { return }
    await fetch(includePlace: needsPlace, includeCredentials: needsCredentials)
  }

  /// Pull-to-refresh — always re-fetch both, in parallel.
  func refresh() async {
    await fetch(includePlace: true, includeCredentials: true)
  }

  private func fetch(includePlace: Bool, includeCredentials: Bool) async {
    output.errorMessage = nil
    if includePlace { output.isLoadingPlace = true }
    if includeCredentials { output.isLoadingCredentials = true }

    async let placeResult: Place? = includePlace ? loadPlace() : nil
    async let credsResult: StreamCredentials? = includeCredentials ? loadCredentials() : nil

    let (place, creds) = await (placeResult, credsResult)

    if includePlace {
      output.isLoadingPlace = false
      if let place {
        output.place = place
      }
    }
    if includeCredentials {
      output.isLoadingCredentials = false
      if let creds {
        output.credentials = creds
      }
    }
  }

  private func loadPlace() async -> Place? {
    do {
      return try await placesService.fetch(slug: slug)
    } catch APIError.unauthorized {
      // SessionService.signOut already fired inside the service; the
      // AppCoordinator will route back to /sign-in on the next render.
      return nil
    } catch {
      surfaceError(error)
      return nil
    }
  }

  private func loadCredentials() async -> StreamCredentials? {
    do {
      return try await credentialsService.fetch(slug: slug)
    } catch APIError.unauthorized {
      return nil
    } catch {
      surfaceError(error)
      return nil
    }
  }

  private func surfaceError(_ error: Error) {
    // First error wins; refresh path will overwrite once the user retries.
    if output.errorMessage == nil {
      output.errorMessage = (error as? LocalizedError)?.errorDescription
        ?? error.localizedDescription
    }
  }

  private func toggleStreamKey() {
    output.streamKeyRevealed.toggle()
  }

  private func copy(value: String, label: String) {
    UIPasteboard.general.string = value
    output.copyToast = "\(label) copied"
  }

  /// Called by the view after the toast's display window elapses.
  func clearToast() {
    output.copyToast = nil
  }

  /// Reflects the row returned by the edit sheet without a re-fetch.
  private func applyEdit(_ place: Place) {
    output.place = place
  }

  /// Deletes this place via the worker (which also cleans up the Cloudflare
  /// Live Input). Returns `true` on success so the view can pop back to the
  /// list; surfaces the error in-place otherwise.
  private func delete() async -> Bool {
    guard !output.isDeleting else { return false }
    output.isDeleting = true
    output.errorMessage = nil
    defer { output.isDeleting = false }

    do {
      try await placesService.delete(slug: slug)
      return true
    } catch APIError.unauthorized {
      // Session already cleared in the service; the coordinator routes to
      // /sign-in on the next render.
      return false
    } catch {
      surfaceError(error)
      return false
    }
  }

  // MARK: - Derived

  /// `https://here-audio.henock-23c.workers.dev/<slug>` — the listener URL
  /// the QR code encodes and the Share sheet shares. Hard-coded host because
  /// the worker base lives in AppEnvironment and the listener path is
  /// `/`-rooted, not `/api/*`.
  static func listenerURL(for slug: String) -> URL {
    // Listeners use the bare worker host (no `/api/` prefix). Fall back to a
    // path-joined form if URL string interpolation fails for any reason.
    URL(string: "https://here-audio.henock-23c.workers.dev/\(slug)")
      ?? URL(fileURLWithPath: "/\(slug)")
  }
}
