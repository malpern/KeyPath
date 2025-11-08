import SwiftUI

/// Compact preflight view shown while initial checks run
struct WizardPreflightView: View {
    @State private var progress: Double = 0.0
    @State private var ticking = true

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                HStack {
                    Spacer()
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .scaleEffect(x: 1.0, y: 1.6, anchor: .center) // thicker bar
                        .animation(.easeInOut(duration: 0.35), value: progress)
                        .frame(width: geo.size.width * 0.6) // 40% shorter than window
                    Spacer()
                }
            }
            .frame(height: 18)
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
