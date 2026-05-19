import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class NewPlaceViewModel: ViewModelType {
  struct Input {
    let setName: @MainActor (String) -> Void
    let setSlug: @MainActor (String) -> Void
    let setTagline: @MainActor (String) -> Void
    let setAccent: @MainActor (String) -> Void
    let setCenter: @MainActor (CLLocationCoordinate2D) -> Void
    let setRadius: @MainActor (Double) -> Void
    let submit: @MainActor () async -> SubmitResult?
  }

  struct Output {
    var name: String
    var slug: String
    var tagline: String
    var accent: String
    var center: CLLocationCoordinate2D?
    var radiusMeters: Double
    var isSubmitting: Bool
    var errorMessage: String?
    var canSubmit: Bool
  }

  struct SubmitResult: Equatable, Hashable, Identifiable {
    let slug: String
    let credentials: StreamCredentials

    var id: String { slug }

    static func == (lhs: SubmitResult, rhs: SubmitResult) -> Bool {
      lhs.slug == rhs.slug
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(slug)
    }
  }

  static let accentSwatches: [String] = [
    "#FF7A1A",  // HERE flame (default)
    "#F4C95D",  // amber
    "#5DD6A0",  // mint
    "#3AB6C1",  // teal
    "#5B7CFA",  // cobalt
    "#A480F2",  // violet
    "#EC6FB0",  // rose
    "#E5E5E5"  // pearl
  ]

  static let defaultAccent = accentSwatches[0]
  static let defaultRadius: Double = 30
  static let minRadius: Double = 10
  static let maxRadius: Double = 500

  private(set) var output: Output

  private var slugManuallyEdited = false

  @ObservationIgnored @Locatable private var service: PlacesService

  init() {
    self.output = Output(
      name: "",
      slug: "",
      tagline: "",
      accent: Self.defaultAccent,
      center: nil,
      radiusMeters: Self.defaultRadius,
      isSubmitting: false,
      errorMessage: nil,
      canSubmit: false
    )
  }

  var input: Input {
    Input(
      setName: { [weak self] in self?.setName($0) },
      setSlug: { [weak self] in self?.setSlug($0) },
      setTagline: { [weak self] in self?.output.tagline = $0 },
      setAccent: { [weak self] in self?.output.accent = $0 },
      setCenter: { [weak self] in self?.setCenter($0) },
      setRadius: { [weak self] in self?.output.radiusMeters = $0 },
      submit: { [weak self] in await self?.submit() }
    )
  }

  private func setName(_ value: String) {
    output.name = value
    if !slugManuallyEdited {
      output.slug = Self.derivedSlug(from: value)
    }
    recomputeCanSubmit()
  }

  private func setSlug(_ value: String) {
    slugManuallyEdited = true
    output.slug = Self.derivedSlug(from: value)
    recomputeCanSubmit()
  }

  private func setCenter(_ value: CLLocationCoordinate2D) {
    output.center = value
    recomputeCanSubmit()
  }

  private func recomputeCanSubmit() {
    output.canSubmit = !output.name.trimmingCharacters(in: .whitespaces).isEmpty
      && Self.isValidSlug(output.slug)
      && output.center != nil
      && !output.isSubmitting
  }

  private func submit() async -> SubmitResult? {
    guard output.canSubmit, let center = output.center else { return nil }
    output.isSubmitting = true
    output.errorMessage = nil
    recomputeCanSubmit()
    defer {
      output.isSubmitting = false
      recomputeCanSubmit()
    }

    let polygon = Geofence.circlePolygon(
      center: center,
      radiusMeters: output.radiusMeters
    )

    do {
      let response = try await service.create(
        name: output.name.trimmingCharacters(in: .whitespaces),
        slug: output.slug,
        tagline: output.tagline.trimmingCharacters(in: .whitespaces),
        accent: output.accent,
        center: center,
        geofence: polygon
      )
      return SubmitResult(slug: response.slug, credentials: response.credentials)
    } catch APIError.unauthorized {
      output.errorMessage = "Your session expired. Sign back in and try again."
      return nil
    } catch APIError.server(let status, let body) {
      output.errorMessage = Self.userMessage(status: status, body: body)
      return nil
    } catch {
      output.errorMessage = (error as? LocalizedError)?.errorDescription
        ?? error.localizedDescription
      return nil
    }
  }

  // MARK: - Helpers

  /// Lowercase, replace runs of non-alphanumerics with single dashes, trim
  /// leading/trailing dashes, cap at 32 chars. Matches the server-side
  /// `^[a-z0-9][a-z0-9-]{1,31}$` regex's character set; server still has the
  /// final say on uniqueness and length-2 minimum.
  static func derivedSlug(from raw: String) -> String {
    let lowered = raw.lowercased()
    var out = ""
    var lastDash = false
    for char in lowered {
      if char.isLetter || char.isNumber {
        out.append(char)
        lastDash = false
      } else if !lastDash && !out.isEmpty {
        out.append("-")
        lastDash = true
      }
    }
    while out.hasSuffix("-") { out.removeLast() }
    if out.count > 32 {
      out = String(out.prefix(32))
      while out.hasSuffix("-") { out.removeLast() }
    }
    return out
  }

  static func isValidSlug(_ slug: String) -> Bool {
    let pattern = "^[a-z0-9][a-z0-9-]{1,31}$"
    return slug.range(of: pattern, options: .regularExpression) != nil
  }

  static func userMessage(status: Int, body: String?) -> String {
    if status == 409 {
      return "That slug is taken — try another."
    }
    if let body, let data = body.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let message = json["error"] as? String, !message.isEmpty {
      return message
    }
    switch status {
    case 402: return "Your plan doesn't include another place. Upgrade to add more."
    case 400: return "Some of the form fields aren't valid yet."
    default: return "Couldn't create that place (\(status))."
    }
  }
}
