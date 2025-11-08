import SwiftUI

/// Compact preflight view shown while initial checks run
struct WizardPreflightView: View {
    @State private var progress: Double = 0.0
    @State private var ticking = true

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .animation(.easeInOut(duration: 0.6), value: progress)
                .padding(.horizontal, 24)

            Text("Setting up KeyPath")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
        .onAppear {
            ticking = true
            // Smooth, time-based ramp to ~90% while checks run; container swaps view when done
            Task { @MainActor in
                while ticking && progress < 0.9 {
                    try? await Task.sleep(nanoseconds: 180_000_000) // ~0.18s
                    progress = min(progress + 0.06, 0.9)
                }
            }
        }
        .onDisappear {
            // Finish animation quickly when replaced by summary
            ticking = false
            withAnimation(.easeInOut(duration: 0.25)) {
                progress = 1.0
            }
        }
    }
}


