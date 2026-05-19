import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Wraps `ASAuthorizationController` for Sign in with Apple. async/await
/// front; generates a raw nonce, SHA-256 hashes it for the Apple request,
/// and returns the raw nonce alongside the identity token so callers can
/// hand both to Supabase's `grant_type=id_token` exchange.
///
/// Says-iOS uses Combine here; we use a continuation because the rest of
/// here-ios is async/await-first.
final class AppleSignInController: NSObject {
  struct Result {
    let identityToken: String
    let rawNonce: String
    let userIdentifier: String
    let fullName: PersonNameComponents?
    let email: String?
  }

  enum SignInError: Error {
    case canceled
    case missingIdentityToken
    case tokenNotUTF8
    case unexpectedCredential
    case underlying(Error)
  }

  private var continuation: CheckedContinuation<Result, Error>?
  private var currentRawNonce: String?

  func signIn() async throws -> Result {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let nonce = Self.makeNonce()
      currentRawNonce = nonce

      let provider = ASAuthorizationAppleIDProvider()
      let request = provider.createRequest()
      request.requestedScopes = [.fullName, .email]
      request.nonce = Self.sha256(nonce)

      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      controller.performRequests()
    }
  }

  private func finish(_ result: Swift.Result<Result, Error>) {
    let continuation = self.continuation
    self.continuation = nil
    self.currentRawNonce = nil
    continuation?.resume(with: result)
  }

  private static func makeNonce(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length
    while remaining > 0 {
      var bytes = [UInt8](repeating: 0, count: 16)
      let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
      precondition(status == errSecSuccess, "SecRandomCopyBytes failed (\(status))")
      for byte in bytes where remaining > 0 {
        if byte < charset.count {
          result.append(charset[Int(byte)])
          remaining -= 1
        }
      }
    }
    return result
  }

  private static func sha256(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInController: ASAuthorizationControllerDelegate {
  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      finish(.failure(SignInError.unexpectedCredential))
      return
    }
    guard let tokenData = credential.identityToken else {
      finish(.failure(SignInError.missingIdentityToken))
      return
    }
    guard let tokenString = String(data: tokenData, encoding: .utf8) else {
      finish(.failure(SignInError.tokenNotUTF8))
      return
    }
    guard let rawNonce = currentRawNonce else {
      finish(.failure(SignInError.unexpectedCredential))
      return
    }
    finish(.success(Result(
      identityToken: tokenString,
      rawNonce: rawNonce,
      userIdentifier: credential.user,
      fullName: credential.fullName,
      email: credential.email
    )))
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    if let authError = error as? ASAuthorizationError, authError.code == .canceled {
      finish(.failure(SignInError.canceled))
      return
    }
    finish(.failure(SignInError.underlying(error)))
  }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInController: ASAuthorizationControllerPresentationContextProviding {
  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    if let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }),
       let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
      return window
    }
    return ASPresentationAnchor()
  }
}
