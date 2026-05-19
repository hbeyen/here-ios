import SwiftUI

/// Modal settings sheet presented from PlacesView. Profile + Account
/// sections only for now; per-place broadcaster settings (Stripe Connect,
/// tip routing, push) belong on the per-place dashboard once that lands.
struct SettingsView: View {
  let user: SessionService.CurrentUser
  let onSignOut: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var isSignOutConfirmed = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Profile") {
          if let displayName = user.displayName, !displayName.isEmpty {
            row(label: "Name", value: displayName)
          }
          if let email = user.email, !email.isEmpty {
            row(label: "Email", value: email)
          }
        }

        Section("Account") {
          Button(role: .destructive) {
            isSignOutConfirmed = true
          } label: {
            HStack {
              Text("Sign Out")
              Spacer()
            }
          }
        }

        Section("About") {
          row(label: "Version", value: Self.versionString)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Color.hereBackground.ignoresSafeArea())
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .alert("Sign out of HERE?", isPresented: $isSignOutConfirmed) {
        Button("Sign Out", role: .destructive) { onSignOut() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("You'll need to sign in again to see your places.")
      }
    }
  }

  @ViewBuilder
  private func row(label: String, value: String) -> some View {
    HStack {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
    }
  }

  private static var versionString: String {
    let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    switch (short, build) {
    case (let s?, let b?): return "\(s) (\(b))"
    case (let s?, nil): return s
    case (nil, let b?): return b
    default: return "—"
    }
  }
}

#Preview {
  SettingsView(
    user: .init(id: "preview-id", email: "you@example.com", displayName: "Henock"),
    onSignOut: {}
  )
}
