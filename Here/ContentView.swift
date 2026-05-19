import SwiftUI

struct ContentView: View {
  var body: some View {
    ZStack {
      Color.hereBackground.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 12) {
        Text("HERE · BROADCASTER")
          .font(.system(size: 11, weight: .medium))
          .tracking(2)
          .foregroundStyle(.white.opacity(0.45))
        Text("Native skeleton")
          .font(.system(size: 36, weight: .bold))
          .foregroundStyle(.white)
        Text("v0.3 — SwiftUI broadcaster app. Architecture lands next.")
          .font(.system(size: 14))
          .foregroundStyle(.white.opacity(0.55))
      }
      .padding(.horizontal, 24)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      .padding(.bottom, 48)
    }
  }
}

extension Color {
  static let hereBackground = Color(red: 5/255, green: 5/255, blue: 5/255)
}

#Preview {
  ContentView()
}
