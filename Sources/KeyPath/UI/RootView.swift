import SwiftUI

struct RootView: View {
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                ContentView()
            } else {
                LoadingView()
            }
        }
        .task {
            // Let AppDelegate handle all activation orchestration
            AppLogger.shared.log("⏳ [RootView] Loading UI")
            // Give SwiftUI a brief moment to initialize, then swap in the main UI
            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
            withAnimation(.easeInOut(duration: 0.2)) { isReady = true }
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header (matches main style, left aligned)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("KeyPath")
                    .font(.largeTitle.weight(.bold))
                Spacer(minLength: 0)
            }
            Text("Loading KeyPath…")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Centered spinner area
            HStack {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Preparing UI…")
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding()
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}
