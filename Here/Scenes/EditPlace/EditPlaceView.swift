import SwiftUI

/// Edit-place sheet — name, tagline, accent. Presented from the per-place
/// dashboard. Mirrors `NewPlaceView`'s Identity section visually (custom
/// dark-theme fields, not SwiftUI `Form`) but drops slug + geofence, which
/// aren't editable here.
struct EditPlaceView: View {
  let onCancel: () -> Void
  let onSaved: (Place) -> Void

  @State private var viewModel: EditPlaceViewModel

  init(place: Place, onCancel: @escaping () -> Void, onSaved: @escaping (Place) -> Void) {
    self.onCancel = onCancel
    self.onSaved = onSaved
    _viewModel = State(wrappedValue: EditPlaceViewModel(place: place))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          identitySection
          if let message = viewModel.output.errorMessage {
            errorBanner(message)
          }
          saveButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
      }
      .background(Color.hereBackground.ignoresSafeArea())
      .navigationTitle("Edit place")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { onCancel() }
            .foregroundStyle(.white.opacity(0.8))
        }
      }
      .toolbarBackground(Color.hereBackground, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .scrollDismissesKeyboard(.interactively)
    }
  }

  // MARK: - Identity

  private var identitySection: some View {
    sectionCard(title: "Identity") {
      VStack(spacing: 14) {
        labeledField(label: "Name", placeholder: "Wicker Park Brewery", value: viewModel.output.name) {
          TextField(
            "",
            text: Binding(
              get: { viewModel.output.name },
              set: { viewModel.input.setName($0) }
            )
          )
          .textInputAutocapitalization(.words)
        }

        labeledField(label: "Tagline (optional)", placeholder: "Live from Side Stage", value: viewModel.output.tagline) {
          TextField(
            "",
            text: Binding(
              get: { viewModel.output.tagline },
              set: { viewModel.input.setTagline($0) }
            )
          )
        }

        accentRow
      }
    }
  }

  private var accentRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Accent")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
          ForEach(NewPlaceViewModel.accentSwatches, id: \.self) { hex in
            Button {
              viewModel.input.setAccent(hex)
            } label: {
              ZStack {
                Circle()
                  .fill(Self.color(from: hex))
                  .frame(width: 28, height: 28)
                if viewModel.output.accent == hex {
                  Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 36, height: 36)
                }
              }
              .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  // MARK: - Save

  private var saveButton: some View {
    Button {
      Task {
        if let place = await viewModel.input.submit() {
          onSaved(place)
        }
      }
    } label: {
      ZStack {
        if viewModel.output.isSubmitting {
          ProgressView()
            .tint(.black)
        } else {
          Text("Save changes")
            .font(.system(size: 15, weight: .semibold))
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(viewModel.output.canSubmit ? Color.white : Color.white.opacity(0.18))
      .foregroundStyle(viewModel.output.canSubmit ? Color.black : Color.white.opacity(0.5))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .disabled(!viewModel.output.canSubmit)
  }

  private func errorBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .padding(.top, 1)
      Text(message)
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.85))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(14)
    .background(Color.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  // MARK: - Layout helpers

  @ViewBuilder
  private func sectionCard<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title.uppercased())
        .font(.system(size: 11, weight: .medium))
        .tracking(2)
        .foregroundStyle(.white.opacity(0.45))
      content()
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
  }

  @ViewBuilder
  private func labeledField<Field: View>(
    label: String,
    placeholder: String,
    value: String,
    @ViewBuilder field: () -> Field
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
      ZStack(alignment: .leading) {
        if value.isEmpty {
          Text(placeholder)
            .foregroundStyle(.white.opacity(0.25))
            .font(.system(size: 15))
        }
        field()
          .font(.system(size: 15))
          .foregroundStyle(.white)
          .tint(.white)
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 12)
      .background(Color.white.opacity(0.06))
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }

  static func color(from hex: String) -> Color {
    let trimmed = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard trimmed.count == 6,
          let value = UInt32(trimmed, radix: 16) else {
      return Color(red: 1.0, green: 0.48, blue: 0.10)
    }
    let red = Double((value >> 16) & 0xFF) / 255.0
    let green = Double((value >> 8) & 0xFF) / 255.0
    let blue = Double(value & 0xFF) / 255.0
    return Color(red: red, green: green, blue: blue)
  }
}

#Preview {
  EditPlaceView(
    place: Place(
      id: "preview-id",
      slug: "wicker-park",
      name: "Wicker Park Brewery",
      tagline: "Live from Side Stage",
      accent: "#FF7A1A",
      isActive: true
    ),
    onCancel: {},
    onSaved: { _ in }
  )
}
