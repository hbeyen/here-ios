import SwiftUI

/// Owner-facing list of places. Mirrors the web broadcaster index
/// (`app/broadcaster/page.tsx`) but slimmed for native — header, list,
/// empty-state CTA, settings sheet. Per-place dashboard and "new place"
/// flow land in follow-up tasks.
struct PlacesView: View {
  let user: SessionService.CurrentUser
  let onSignOut: () -> Void

  @State private var viewModel = PlacesViewModel()
  @State private var isSettingsPresented = false
  @State private var isNewPlacePresented = false
  @State private var justCreated: NewPlaceViewModel.SubmitResult?

  var body: some View {
    NavigationStack {
      ZStack {
        Color.hereBackground.ignoresSafeArea()
        content
      }
      .navigationBarHidden(true)
      .navigationDestination(item: $justCreated) { created in
        PlaceDashboardView(
          slug: created.slug,
          credentials: created.credentials,
          onDeleted: { Task { await viewModel.input.refresh() } }
        )
      }
    }
    .task {
      await viewModel.input.load()
    }
    .sheet(isPresented: $isSettingsPresented) {
      SettingsView(user: user, onSignOut: {
        isSettingsPresented = false
        onSignOut()
      })
    }
    .sheet(isPresented: $isNewPlacePresented) {
      NewPlaceView(
        onCancel: { isNewPlacePresented = false },
        onCreated: { result in
          isNewPlacePresented = false
          Task {
            await viewModel.input.refresh()
            // Push the dashboard after the sheet finishes dismissing so the
            // navigation transition reads cleanly.
            try? await Task.sleep(nanoseconds: 350_000_000)
            justCreated = result
          }
        }
      )
    }
  }

  @ViewBuilder
  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding(.horizontal, 24)
        .padding(.top, 48)

      switch viewModel.output.status {
      case .loading:
        loadingView
      case .empty:
        emptyState
      case .loaded:
        placesList
      case .failed:
        errorView
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 6) {
        Text("HERE · BROADCASTER")
          .font(.system(size: 11, weight: .medium))
          .tracking(2)
          .foregroundStyle(.white.opacity(0.45))
        Text(viewModel.output.status == .empty ? "Welcome" : "Your places")
          .font(.system(size: 36, weight: .semibold))
          .foregroundStyle(.white)
        if let name = user.displayName, !name.isEmpty {
          Text(name)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.55))
        }
      }
      Spacer()
      if viewModel.output.status == .loaded {
        Button {
          isNewPlacePresented = true
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("New place")
      }
      Button {
        isSettingsPresented = true
      } label: {
        Image(systemName: "gearshape")
          .font(.system(size: 18, weight: .regular))
          .foregroundStyle(.white.opacity(0.7))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Settings")
    }
  }

  private var loadingView: some View {
    VStack {
      Spacer()
      ProgressView()
        .tint(.white)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var emptyState: some View {
    VStack(spacing: 0) {
      Spacer()
      Image(systemName: "mappin.and.ellipse")
        .font(.system(size: 56, weight: .light))
        .foregroundStyle(.white.opacity(0.65))
        .padding(.bottom, 24)
      Text("Create your first place")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(.white)
      Text("A place is a GPS-fenced venue. Name it, draw the fence — we wire your stream.")
        .font(.system(size: 14))
        .foregroundStyle(.white.opacity(0.6))
        .multilineTextAlignment(.center)
        .padding(.top, 8)
        .padding(.horizontal, 32)
      Button {
        isNewPlacePresented = true
      } label: {
        Text("Start")
          .font(.system(size: 15, weight: .semibold))
          .frame(maxWidth: .infinity)
          .frame(height: 50)
          .background(.white)
          .foregroundStyle(.black)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .padding(.horizontal, 24)
      .padding(.top, 32)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var placesList: some View {
    List {
      Section {
        ForEach(viewModel.output.places) { place in
          NavigationLink {
            PlaceDashboardView(
              place: place,
              onDeleted: { Task { await viewModel.input.refresh() } }
            )
          } label: {
            PlaceRow(place: place)
          }
          .listRowBackground(Color.white.opacity(0.04))
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .refreshable {
      await viewModel.input.refresh()
    }
  }

  private var errorView: some View {
    VStack(spacing: 12) {
      Spacer()
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 32, weight: .light))
        .foregroundStyle(.white.opacity(0.65))
      Text(viewModel.output.errorMessage ?? "Couldn't load your places.")
        .font(.system(size: 14))
        .foregroundStyle(.white.opacity(0.75))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
      Button {
        Task { await viewModel.input.load() }
      } label: {
        Text("Try again")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 18)
          .padding(.vertical, 10)
          .background(.white.opacity(0.1))
          .clipShape(Capsule())
      }
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }
}

private struct PlaceRow: View {
  let place: Place

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(place.name)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(.white)
        Text("/\(place.slug)")
          .font(.system(size: 13))
          .foregroundStyle(.white.opacity(0.5))
      }
      Spacer()
      Circle()
        .fill(accentColor(place.accent))
        .frame(width: 8, height: 8)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .background(.white.opacity(0.04))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func accentColor(_ hex: String) -> Color {
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
  PlacesView(
    user: .init(id: "preview-id", email: "you@example.com", displayName: "Henock"),
    onSignOut: {}
  )
}
