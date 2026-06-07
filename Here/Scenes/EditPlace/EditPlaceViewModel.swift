import Foundation
import Observation

/// Edits an existing place's metadata: name, tagline, accent. Slug and
/// geofence are deliberately omitted (slug is identity; geofence editing is a
/// separate MapKit task). Reuses `NewPlaceViewModel.accentSwatches` so the
/// swatch palette stays in one place.
@MainActor
@Observable
final class EditPlaceViewModel: ViewModelType {
  struct Input {
    let setName: @MainActor (String) -> Void
    let setTagline: @MainActor (String) -> Void
    let setAccent: @MainActor (String) -> Void
    let submit: @MainActor () async -> Place?
  }

  struct Output {
    var name: String
    var tagline: String
    var accent: String
    var isSubmitting: Bool
    var errorMessage: String?
    var canSubmit: Bool
  }

  private(set) var output: Output

  private let slug: String
  @ObservationIgnored @Locatable private var service: PlacesService

  init(place: Place) {
    self.slug = place.slug
    self.output = Output(
      name: place.name,
      tagline: place.tagline,
      accent: place.accent,
      isSubmitting: false,
      errorMessage: nil,
      canSubmit: true
    )
  }

  var input: Input {
    Input(
      setName: { [weak self] in self?.setName($0) },
      setTagline: { [weak self] in self?.output.tagline = $0 },
      setAccent: { [weak self] in self?.output.accent = $0 },
      submit: { [weak self] in await self?.submit() }
    )
  }

  private func setName(_ value: String) {
    output.name = value
    output.canSubmit = !value.trimmingCharacters(in: .whitespaces).isEmpty
      && !output.isSubmitting
  }

  private func submit() async -> Place? {
    let name = output.name.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return nil }

    output.isSubmitting = true
    output.errorMessage = nil
    output.canSubmit = false
    defer {
      output.isSubmitting = false
      output.canSubmit = !output.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    do {
      return try await service.update(
        slug: slug,
        name: name,
        tagline: output.tagline.trimmingCharacters(in: .whitespaces),
        accent: output.accent
      )
    } catch APIError.unauthorized {
      output.errorMessage = "Your session expired. Sign back in and try again."
      return nil
    } catch {
      output.errorMessage = (error as? LocalizedError)?.errorDescription
        ?? error.localizedDescription
      return nil
    }
  }
}
