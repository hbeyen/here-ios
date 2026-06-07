import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Per-place broadcaster dashboard. Mirrors the web `/broadcaster/[slug]`
/// surface at section level (credentials, distribution, go-live placeholder)
/// in the native dark-on-black aesthetic established by `PlacesView`.
///
/// Two entry shapes are supported via the matching VM init:
/// - **List-tap**: `PlaceDashboardView(place: Place)` — Place is in hand,
///   credentials fetched on appear.
/// - **Just-created deep-link**: `PlaceDashboardView(slug:, credentials:)` —
///   credentials are in hand, Place is fetched on appear.
struct PlaceDashboardView: View {
  private let slug: String
  private let onDeleted: () -> Void
  @State private var viewModel: PlaceDashboardViewModel
  @State private var isEditPresented = false
  @State private var isDeleteConfirmed = false

  @Environment(\.dismiss) private var dismiss

  init(place: Place, onDeleted: @escaping () -> Void = {}) {
    self.slug = place.slug
    self.onDeleted = onDeleted
    _viewModel = State(wrappedValue: PlaceDashboardViewModel(
      slug: place.slug,
      place: place,
      prefetchedCredentials: nil
    ))
  }

  init(slug: String, credentials: StreamCredentials?, onDeleted: @escaping () -> Void = {}) {
    self.slug = slug
    self.onDeleted = onDeleted
    _viewModel = State(wrappedValue: PlaceDashboardViewModel(
      slug: slug,
      place: nil,
      prefetchedCredentials: credentials
    ))
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.hereBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          header
          credentialsSection
          distributionSection
          goLiveSection
          dangerZone
          if let error = viewModel.output.errorMessage {
            errorBanner(error)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 48)
      }
      .refreshable {
        await viewModel.input.refresh()
      }

      if let toast = viewModel.output.copyToast {
        copyToast(toast)
          .padding(.bottom, 32)
          .transition(.opacity)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Color.hereBackground, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbarColorScheme(.dark, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Edit") { isEditPresented = true }
          .disabled(viewModel.output.place == nil)
      }
    }
    .sheet(isPresented: $isEditPresented) {
      if let place = viewModel.output.place {
        EditPlaceView(
          place: place,
          onCancel: { isEditPresented = false },
          onSaved: { updated in
            isEditPresented = false
            viewModel.input.applyEdit(updated)
          }
        )
      }
    }
    .alert("Delete \(viewModel.output.place?.name ?? "this place")?", isPresented: $isDeleteConfirmed) {
      Button("Delete", role: .destructive) {
        Task {
          if await viewModel.input.delete() {
            onDeleted()
            dismiss()
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This can't be undone. Listeners will no longer reach this place.")
    }
    .task {
      await viewModel.input.load()
    }
    .onChange(of: viewModel.output.copyToast) { _, newValue in
      guard newValue != nil else { return }
      Task {
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        viewModel.clearToast()
      }
    }
  }

  // MARK: - Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        if let place = viewModel.output.place {
          Text(place.name)
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(2)
          Circle()
            .fill(Self.color(from: place.accent))
            .frame(width: 9, height: 9)
            .padding(.bottom, 6)
        } else {
          Text(viewModel.output.isLoadingPlace ? "Loading…" : "/\(slugForHeader)")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
        }
        Spacer(minLength: 0)
      }

      Text("/\(slugForHeader)")
        .font(.system(size: 14))
        .foregroundStyle(.white.opacity(0.55))

      if let tagline = viewModel.output.place?.tagline, !tagline.isEmpty {
        Text(tagline)
          .font(.system(size: 13))
          .foregroundStyle(.white.opacity(0.55))
          .padding(.top, 2)
      }
    }
  }

  private var slugForHeader: String {
    viewModel.output.place?.slug ?? slug
  }

  // MARK: - Credentials

  private var credentialsSection: some View {
    sectionCard(title: "Stream credentials") {
      VStack(spacing: 12) {
        if viewModel.output.isLoadingCredentials && viewModel.output.credentials == nil {
          credentialsLoading
        } else if let creds = viewModel.output.credentials {
          credentialsRows(creds)
        } else {
          Text("Credentials not available yet.")
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  private var credentialsLoading: some View {
    HStack {
      ProgressView()
        .tint(.white)
      Text("Fetching stream key…")
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.55))
      Spacer()
    }
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private func credentialsRows(_ creds: StreamCredentials) -> some View {
    let rtmpsURL = creds.rtmps?.url ?? ""
    let streamKey = creds.rtmps?.streamKey ?? ""

    credentialsRow(
      label: "RTMPS URL",
      value: rtmpsURL,
      placeholder: "Not provisioned",
      monospaced: true,
      copyLabel: "RTMPS URL"
    )

    credentialsRow(
      label: "Stream key",
      value: viewModel.output.streamKeyRevealed
        ? streamKey
        : String(repeating: "•", count: max(min(streamKey.count, 32), 8)),
      placeholder: "Not provisioned",
      monospaced: true,
      copyLabel: "Stream key",
      trailing: {
        Button {
          viewModel.input.toggleStreamKey()
        } label: {
          Text(viewModel.output.streamKeyRevealed ? "Hide" : "Show")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(streamKey.isEmpty)
        .opacity(streamKey.isEmpty ? 0.4 : 1.0)
      }
    )

    if let playback = creds.playback?.hls, !playback.isEmpty {
      credentialsRow(
        label: "Playback (HLS)",
        value: playback,
        placeholder: "",
        monospaced: true,
        copyLabel: "Playback URL"
      )
    }
  }

  @ViewBuilder
  private func credentialsRow<Trailing: View>(
    label: String,
    value: String,
    placeholder: String,
    monospaced: Bool,
    copyLabel: String,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .tracking(1)
        .foregroundStyle(.white.opacity(0.45))
      HStack(spacing: 10) {
        Text(value.isEmpty ? placeholder : value)
          .font(.system(size: 13, design: monospaced ? .monospaced : .default))
          .foregroundStyle(value.isEmpty ? .white.opacity(0.4) : .white)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: .infinity, alignment: .leading)
        trailing()
        Button {
          viewModel.input.copy(value, copyLabel)
        } label: {
          Image(systemName: "doc.on.doc")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(value.isEmpty)
        .opacity(value.isEmpty ? 0.4 : 1.0)
        .accessibilityLabel("Copy \(label)")
      }
    }
  }

  @ViewBuilder
  private func credentialsRow(
    label: String,
    value: String,
    placeholder: String,
    monospaced: Bool,
    copyLabel: String
  ) -> some View {
    credentialsRow(
      label: label,
      value: value,
      placeholder: placeholder,
      monospaced: monospaced,
      copyLabel: copyLabel,
      trailing: { EmptyView() }
    )
  }

  // MARK: - Distribution

  private var distributionSection: some View {
    sectionCard(title: "Distribution") {
      VStack(alignment: .center, spacing: 16) {
        let listener = PlaceDashboardViewModel.listenerURL(for: slugForHeader)
        if let image = Self.qr(for: listener.absoluteString) {
          Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: 200, height: 200)
            .padding(12)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(width: 200, height: 200)
            .overlay(
              Text("QR unavailable")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            )
        }

        Text(listener.absoluteString)
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(.white.opacity(0.65))
          .multilineTextAlignment(.center)
          .padding(.horizontal, 8)

        HStack(spacing: 10) {
          Button {
            viewModel.input.copy(listener.absoluteString, "Listener URL")
          } label: {
            Label("Copy", systemImage: "doc.on.doc")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(.white)
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
              .background(Color.white.opacity(0.1))
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)

          ShareLink(item: listener) {
            Label("Share", systemImage: "square.and.arrow.up")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(.black)
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
              .background(.white)
              .clipShape(Capsule())
          }
        }
      }
      .frame(maxWidth: .infinity)
    }
  }

  // MARK: - Go live (placeholder)

  private var goLiveSection: some View {
    sectionCard(title: "Go live") {
      NavigationLink {
        ReplayKitPlaceholderView()
      } label: {
        HStack(spacing: 14) {
          Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          VStack(alignment: .leading, spacing: 4) {
            Text("Broadcast from this device")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(.white)
            Text("ReplayKit broadcast extension — coming in task 005")
              .font(.system(size: 12))
              .foregroundStyle(.white.opacity(0.55))
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
        }
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Danger zone

  private var dangerZone: some View {
    Button {
      isDeleteConfirmed = true
    } label: {
      HStack(spacing: 12) {
        if viewModel.output.isDeleting {
          ProgressView()
            .tint(.red)
        } else {
          Image(systemName: "trash")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.red)
        }
        Text("Delete place")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(.red)
        Spacer()
      }
      .padding(16)
      .frame(maxWidth: .infinity)
      .background(Color.red.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(viewModel.output.isDeleting || viewModel.output.place == nil)
  }

  // MARK: - Toast + error

  private func copyToast(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.white)
      .padding(.horizontal, 18)
      .padding(.vertical, 10)
      .background(.black.opacity(0.8))
      .clipShape(Capsule())
      .overlay(
        Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
      )
  }

  private func errorBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 8) {
        Text(message)
          .font(.system(size: 13))
          .foregroundStyle(.white.opacity(0.85))
        Button {
          Task { await viewModel.input.refresh() }
        } label: {
          Text("Try again")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
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

  // MARK: - QR generation

  static func qr(for value: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(value.utf8)
    filter.correctionLevel = "H"
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    let context = CIContext()
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
      return nil
    }
    return UIImage(cgImage: cgImage)
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

private struct ReplayKitPlaceholderView: View {
  var body: some View {
    ZStack {
      Color.hereBackground.ignoresSafeArea()
      VStack(spacing: 12) {
        Image(systemName: "dot.radiowaves.left.and.right")
          .font(.system(size: 40, weight: .light))
          .foregroundStyle(.white.opacity(0.6))
        Text("Broadcast from this device")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.white)
        Text("ReplayKit integration lands in task 005.")
          .font(.system(size: 13))
          .foregroundStyle(.white.opacity(0.55))
      }
    }
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview("List-tap entry") {
  NavigationStack {
    PlaceDashboardView(place: Place(
      id: "preview-id",
      slug: "wicker-park",
      name: "Wicker Park Brewery",
      tagline: "Live from Side Stage",
      accent: "#FF7A1A",
      isActive: true
    ))
  }
}

#Preview("Just-created deep-link") {
  NavigationStack {
    PlaceDashboardView(
      slug: "wicker-park",
      credentials: StreamCredentials(
        rtmps: .init(
          url: "rtmps://live.cloudflare.com:443/live/",
          streamKey: "abcdef1234567890abcdef1234567890"
        ),
        webRTC: nil,
        playback: .init(
          hls: "https://customer-…/manifest/video.m3u8",
          dash: nil
        )
      )
    )
  }
}
