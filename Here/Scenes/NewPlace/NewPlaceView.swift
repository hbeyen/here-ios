import CoreLocation
import MapKit
import SwiftUI

/// Create-a-place wizard, presented as a full-screen sheet from PlacesView.
///
/// Three sections: Identity (name, slug, tagline, accent), Geofence (MapKit
/// map with a fixed crosshair + radius slider), and a Submit button. We pin
/// a crosshair to the map's visual center and treat camera pans as moving
/// the geofence centre — far simpler than implementing a draggable MapKit
/// annotation, and matches Apple's own "drop a pin where I'm looking" pattern
/// (Wallet add-card location, Find My pin drop).
struct NewPlaceView: View {
  let onCancel: () -> Void
  let onCreated: (String) -> Void

  @State private var viewModel = NewPlaceViewModel()
  @State private var cameraPosition: MapCameraPosition = .region(
    Self.defaultRegion
  )
  @State private var hasCenteredOnUser = false
  @StateObject private var locationProvider = LocationProvider()

  private static let defaultRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
  )

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          identitySection
          geofenceSection
          if let message = viewModel.output.errorMessage {
            errorBanner(message)
          }
          submitButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
      }
      .background(Color.hereBackground.ignoresSafeArea())
      .navigationTitle("New place")
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
    .onAppear {
      locationProvider.requestPermission()
    }
    .onReceive(locationProvider.$lastLocation.compactMap { $0 }) { coord in
      guard !hasCenteredOnUser else { return }
      hasCenteredOnUser = true
      cameraPosition = .region(
        MKCoordinateRegion(
          center: coord,
          span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        )
      )
      viewModel.input.setCenter(coord)
    }
  }

  // MARK: - Identity

  private var identitySection: some View {
    sectionCard(title: "Identity") {
      VStack(spacing: 14) {
        labeledField(label: "Name", placeholder: "Wicker Park Brewery") {
          TextField(
            "",
            text: Binding(
              get: { viewModel.output.name },
              set: { viewModel.input.setName($0) }
            )
          )
          .textInputAutocapitalization(.words)
        }

        labeledField(label: "Slug", placeholder: "wicker-park") {
          TextField(
            "",
            text: Binding(
              get: { viewModel.output.slug },
              set: { viewModel.input.setSlug($0) }
            )
          )
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)
        } caption: {
          Text("listeners visit here-audio.henock-23c.workers.dev/\(viewModel.output.slug.isEmpty ? "…" : viewModel.output.slug)")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
        }

        labeledField(label: "Tagline (optional)", placeholder: "Live from Side Stage") {
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

  // MARK: - Geofence

  private var geofenceSection: some View {
    sectionCard(title: "Geofence") {
      VStack(alignment: .leading, spacing: 12) {
        ZStack {
          Map(position: $cameraPosition) {
            if let center = viewModel.output.center {
              MapCircle(center: center, radius: viewModel.output.radiusMeters)
                .foregroundStyle(Self.color(from: viewModel.output.accent).opacity(0.18))
                .stroke(Self.color(from: viewModel.output.accent).opacity(0.7), lineWidth: 1.5)
            }
          }
          .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
          .frame(height: 260)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .onMapCameraChange(frequency: .continuous) { context in
            viewModel.input.setCenter(context.region.center)
          }

          // Fixed crosshair anchored to the map's visual center. The user
          // pans the map under it to set the geofence centre.
          Image(systemName: "scope")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .allowsHitTesting(false)
        }

        HStack {
          Text("Radius")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
          Spacer()
          Text("\(Int(viewModel.output.radiusMeters)) m")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .monospacedDigit()
        }

        Slider(
          value: Binding(
            get: { viewModel.output.radiusMeters },
            set: { viewModel.input.setRadius($0) }
          ),
          in: NewPlaceViewModel.minRadius...NewPlaceViewModel.maxRadius
        )
        .tint(Self.color(from: viewModel.output.accent))

        Text(geofenceCaption)
          .font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.45))
      }
    }
  }

  private var geofenceCaption: String {
    if let center = viewModel.output.center {
      return String(
        format: "Centre %.5f, %.5f · listeners inside this fence will hear your stream.",
        center.latitude,
        center.longitude
      )
    }
    return "Drag the map to set the centre. Listeners inside the fence will hear your stream."
  }

  // MARK: - Submit

  private var submitButton: some View {
    Button {
      Task {
        if let result = await viewModel.input.submit() {
          onCreated(result.slug)
        }
      }
    } label: {
      ZStack {
        if viewModel.output.isSubmitting {
          ProgressView()
            .tint(.black)
        } else {
          Text("Create place")
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
  private func labeledField<Field: View, Caption: View>(
    label: String,
    placeholder: String,
    @ViewBuilder field: () -> Field,
    @ViewBuilder caption: () -> Caption
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
      ZStack(alignment: .leading) {
        // Manual placeholder so the dark theme reads correctly.
        if fieldValue(for: label).isEmpty {
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
      caption()
    }
  }

  @ViewBuilder
  private func labeledField<Field: View>(
    label: String,
    placeholder: String,
    @ViewBuilder field: () -> Field
  ) -> some View {
    labeledField(label: label, placeholder: placeholder, field: field) {
      EmptyView()
    }
  }

  private func fieldValue(for label: String) -> String {
    switch label {
    case "Name": return viewModel.output.name
    case "Slug": return viewModel.output.slug
    case let l where l.hasPrefix("Tagline"): return viewModel.output.tagline
    default: return ""
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

/// Thin CoreLocation wrapper that just asks for permission and forwards the
/// first non-stale fix. The NewPlace flow uses this to centre the map on the
/// user once — it doesn't keep tracking after that.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published var lastLocation: CLLocationCoordinate2D?

  private let manager = CLLocationManager()

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func requestPermission() {
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    default:
      break
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    Task { @MainActor in
      if status == .authorizedAlways || status == .authorizedWhenInUse {
        manager.requestLocation()
      }
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard let coord = locations.last?.coordinate else { return }
    Task { @MainActor in
      self.lastLocation = coord
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager,
    didFailWithError error: Error
  ) {
    // Permission denied / location services off — silently fall back to the
    // default map region; user can still drag the pin where they want.
  }
}

#Preview {
  NewPlaceView(onCancel: {}, onCreated: { _ in })
}
