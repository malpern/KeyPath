import SwiftUI

/// Compact preflight view shown while initial checks run
struct WizardPreflightView: View {
    @State private var progress: Double = 0.0
    @State private var ticking = true

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .animation(.easeInOut(duration: 0.35), value: progress)
                .padding(.horizontal, 24)

            Text("Setting up KeyPath")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
        .onAppear {
            ticking = true
            // Smooth, time-based ramp to ~95% while checks run; container swaps view when done
            Task { @MainActor in
                while ticking && progress < 0.95 {
                    try? await Task.sleep(nanoseconds: 120_000_000) // ~0.12s
                    progress = min(progress + 0.10, 0.95)
                }
            }
        }
        .onDisappear {
            // Finish animation quickly when replaced by summary
            ticking = false
            withAnimation(.easeInOut(duration: 0.2)) {
                progress = 1.0
            }
        }
    }
}
