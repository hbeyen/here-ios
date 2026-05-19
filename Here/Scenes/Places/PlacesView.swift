import SwiftUI

/// Placeholder post-auth surface. Replaced by the real Places list scene in
/// a follow-up PR — for now it just proves the SiwA round-trip succeeded
/// and lets the user sign out to retest.
struct PlacesView: View {
  let user: SessionService.CurrentUser
  let onSignOut: () -> Void

  var body: some View {
    ZStack {
      Color.hereBackground.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 16) {
        Text("HERE · BROADCASTER")
          .font(.system(size: 11, weight: .medium))
          .tracking(2)
          .foregroundStyle(.white.opacity(0.45))
        Text("Signed in")
          .font(.system(size: 36, weight: .bold))
          .foregroundStyle(.white)
        if let name = user.displayName, !name.isEmpty {
          Text(name)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
        }
        if let email = user.email {
          Text(email)
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.55))
        }
        Text("user id: \(user.id)")
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.white.opacity(0.35))
          .padding(.top, 4)
        Spacer()
        Button(role: .destructive) {
          onSignOut()
        } label: {
          Text("Sign out")
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(.white.opacity(0.08))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 48)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

#Preview {
  PlacesView(
    user: .init(id: "preview-id", email: "you@example.com", displayName: "Henock"),
    onSignOut: {}
  )
}
