import SwiftUI

/// Modal settings sheet presented from PlacesView. Profile + Account
/// sections only for now; per-place broadcaster settings (Stripe Connect,
/// tip routing, push) belong on the per-place dashboard once that lands.
struct SettingsView: View {
  let user: SessionService.CurrentUser
  let onSignOut: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var viewModel: SettingsViewModel
  @State private var isSignOutConfirmed = false
  @FocusState private var nameFieldFocused: Bool

  init(user: SessionService.CurrentUser, onSignOut: @escaping () -> Void) {
    self.user = user
    self.onSignOut = onSignOut
    _viewModel = State(wrappedValue: SettingsViewModel(displayName: user.displayName))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Profile") {
          displayNameRow
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

  // MARK: - Display name

  @ViewBuilder
  private var displayNameRow: some View {
    if viewModel.output.isEditingName {
      VStack(alignment: .leading, spacing: 10) {
        TextField(
          "Display name",
          text: Binding(
            get: { viewModel.output.draftName },
            set: { viewModel.input.setDraftName($0) }
          )
        )
        .textInputAutocapitalization(.words)
        .submitLabel(.done)
        .focused($nameFieldFocused)
        .onSubmit { Task { await viewModel.input.saveName() } }
        .disabled(viewModel.output.isSaving)

        if let error = viewModel.output.errorMessage {
          Text(error)
            .font(.system(size: 12))
            .foregroundStyle(.orange)
        }

        HStack(spacing: 12) {
          Button("Cancel") {
            viewModel.input.cancelEditingName()
            nameFieldFocused = false
          }
          .disabled(viewModel.output.isSaving)
          Spacer()
          if viewModel.output.isSaving {
            ProgressView()
          } else {
            Button("Save") {
              Task {
                await viewModel.input.saveName()
                nameFieldFocused = false
              }
            }
            .fontWeight(.semibold)
          }
        }
      }
      .onAppear { nameFieldFocused = true }
    } else {
      Button {
        viewModel.input.beginEditingName()
      } label: {
        HStack {
          Text("Name")
            .foregroundStyle(.secondary)
          Spacer()
          if let name = viewModel.output.displayName, !name.isEmpty {
            Text(name)
              .foregroundStyle(.primary)
              .multilineTextAlignment(.trailing)
              .lineLimit(2)
          } else {
            Text("Add")
              .foregroundStyle(.tint)
          }
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
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
