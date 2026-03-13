import SwiftUI

/// Compact preflight view shown while initial checks run
public struct WizardPreflightView: View {
    @Binding public var progress: Double

    public init(progress: Binding<Double> = .constant(0.0)) {
        _progress = progress
    }

    public var body: some View {
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
        .background(WizardDesign.Colors.wizardBackground) // Dark mode-aware background
    }
}
