import AuthenticationServices
import Foundation
import Observation

@MainActor
@Observable
final class SignInViewModel: ViewModelType {
  struct Input {
    let signInWithApple: @MainActor () async -> Void
  }

  struct Output {
    var status: Status
    var errorMessage: String?
  }

  enum Status: Equatable {
    case idle
    case authenticating
    case signedIn
  }

  private(set) var output = Output(status: .idle, errorMessage: nil)

  var input: Input {
    Input(signInWithApple: { [weak self] in await self?.handleSignInWithApple() })
  }

  @ObservationIgnored @Locatable private var session: SessionService
  @ObservationIgnored @Locatable private var supabase: SupabaseAuthClient
  @ObservationIgnored private let appleController: AppleSignInController
  @ObservationIgnored private let onSignedIn: () -> Void

  init(
    appleController: AppleSignInController = AppleSignInController(),
    onSignedIn: @escaping () -> Void
  ) {
    self.appleController = appleController
    self.onSignedIn = onSignedIn
  }

  private func handleSignInWithApple() async {
    output.errorMessage = nil
    output.status = .authenticating
    do {
      let appleResult = try await appleController.signIn()
      let displayName = Self.formatName(appleResult.fullName)
      let supabaseSession = try await supabase.signInWithApple(
        idToken: appleResult.identityToken,
        nonce: appleResult.rawNonce
      )
      try session.adopt(session: supabaseSession, displayName: displayName ?? appleResult.email)
      output.status = .signedIn
      onSignedIn()
    } catch AppleSignInController.SignInError.canceled {
      output.status = .idle
    } catch {
      output.status = .idle
      output.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }

  private static func formatName(_ components: PersonNameComponents?) -> String? {
    guard let components else { return nil }
    let formatter = PersonNameComponentsFormatter()
    formatter.style = .default
    let formatted = formatter.string(from: components).trimmingCharacters(in: .whitespaces)
    return formatted.isEmpty ? nil : formatted
  }
}
