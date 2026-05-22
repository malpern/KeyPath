import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct HoldTimingSliderRow: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    let currentValue: Int
    var onSliderReleased: (() -> Void)?
    var onValueChanged: ((Double) -> Void)?

    @State private var isEditing = false

    private var invertedBinding: Binding<Double> {
        Binding(
            get: { range.upperBound + range.lowerBound - value },
            set: { newInverted in
                let raw = range.upperBound + range.lowerBound - newInverted
                value = raw
                onValueChanged?(raw)
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Label("Prefer letters", systemImage: "character.cursor.ibeam")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Slider(value: invertedBinding, in: range, step: step) { editing in
                isEditing = editing
                if !editing {
                    onSliderReleased?()
                }
            }
            .frame(maxWidth: 200)
            .accessibilityIdentifier("pack-detail-hold-timing-slider")
            .accessibilityLabel("Hold timing")
            .accessibilityValue("\(currentValue)\(suffix)")
            .overlay(alignment: .top) {
                if isEditing {
                    GeometryReader { geo in
                        let fraction = (range.upperBound + range.lowerBound - value - range.lowerBound) / (range.upperBound - range.lowerBound)
                        let trackInset: CGFloat = 10
                        let trackWidth = geo.size.width - trackInset * 2
                        let thumbX = trackInset + trackWidth * fraction

                        Text("\(currentValue) ms")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                            .fixedSize()
                            .position(x: thumbX, y: -14)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }

            Label("Prefer modifiers", systemImage: "command")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .animation(.easeInOut(duration: 0.15), value: isEditing)
    }
}
