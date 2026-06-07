import Foundation
import Observation

/// Backs the Settings sheet. Today its only stateful job is the editable
/// display name; profile email + version are static reads the view does
/// inline. Sign-out stays a closure owned by the parent so the coordinator
/// can tear down the session.
@MainActor
@Observable
final class SettingsViewModel: ViewModelType {
  struct Input {
    let beginEditingName: @MainActor () -> Void
    let setDraftName: @MainActor (String) -> Void
    let cancelEditingName: @MainActor () -> Void
    let saveName: @MainActor () async -> Void
  }

  struct Output {
    var displayName: String?
    var isEditingName: Bool
    var draftName: String
    var isSaving: Bool
    var errorMessage: String?
  }

  private(set) var output: Output

  @ObservationIgnored @Locatable private var auth: SupabaseAuthClient
  @ObservationIgnored @Locatable private var session: SessionService

  init(displayName: String?) {
    self.output = Output(
      displayName: displayName,
      isEditingName: false,
      draftName: displayName ?? "",
      isSaving: false,
      errorMessage: nil
    )
  }

  var input: Input {
    Input(
      beginEditingName: { [weak self] in self?.beginEditingName() },
      setDraftName: { [weak self] in self?.output.draftName = $0 },
      cancelEditingName: { [weak self] in self?.cancelEditingName() },
      saveName: { [weak self] in await self?.saveName() }
    )
  }

  private func beginEditingName() {
    output.draftName = output.displayName ?? ""
    output.errorMessage = nil
    output.isEditingName = true
  }

  private func cancelEditingName() {
    output.isEditingName = false
    output.errorMessage = nil
  }

  private func saveName() async {
    let trimmed = output.draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      output.errorMessage = "Name can't be empty."
      return
    }
    guard let accessToken = session.accessToken else {
      output.errorMessage = "Your session expired. Sign back in and try again."
      return
    }

    output.isSaving = true
    output.errorMessage = nil
    defer { output.isSaving = false }

    do {
      let user = try await auth.updateDisplayName(trimmed, accessToken: accessToken)
      let resolved = user.displayName ?? trimmed
      try session.setDisplayName(resolved)
      output.displayName = resolved
      output.isEditingName = false
    } catch APIError.unauthorized {
      output.errorMessage = "Your session expired. Sign back in and try again."
    } catch {
      output.errorMessage = (error as? LocalizedError)?.errorDescription
        ?? error.localizedDescription
    }
  }
}
