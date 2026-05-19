import AuthenticationServices
import SwiftUI

struct SignInView: View {
  @State var viewModel: SignInViewModel

  var body: some View {
    ZStack {
      Color.hereBackground.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 16) {
        Spacer()
        Text("HERE")
          .font(.system(size: 48, weight: .bold))
          .foregroundStyle(.white)
        Text("Geofenced live audio for venues, performers, and tours.")
          .font(.system(size: 16))
          .foregroundStyle(.white.opacity(0.6))
        Spacer()
        if let message = viewModel.output.errorMessage {
          Text(message)
            .font(.system(size: 13))
            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.45))
            .padding(.bottom, 4)
        }
        SignInWithAppleButton(.signIn) { _ in
          // Apple adds its own attribute to the request inside the controller;
          // we drive the actual flow ourselves so we own the nonce.
        } onCompletion: { _ in
          // Same — the button is decorative here; tap routes through the
          // controller below.
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          // Cover Apple's button hit-area with our own so we control the flow.
          Button {
            Task { await viewModel.input.signInWithApple() }
          } label: {
            Color.clear
          }
          .disabled(viewModel.output.status == .authenticating)
        }
        .opacity(viewModel.output.status == .authenticating ? 0.6 : 1)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 48)
    }
  }
}

#Preview {
  SignInView(viewModel: SignInViewModel(onSignedIn: {}))
}
