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

    /// Debounces `onSliderReleased` for accessibility Increment/Decrement
    /// actions. Unlike a mouse drag — which fires `onValueChanged`
    /// continuously but `onSliderReleased` exactly once, on release — each
    /// VoiceOver arrow-key press is its own discrete gesture, so without
    /// debouncing, a user pressing Increment several times in a row would
    /// trigger a full config write + TCP reload + timing-preview animation
    /// restart (see `onSliderReleased` callers) after *every* keypress
    /// instead of once the value settles.
    @State private var axReleaseTask: Task<Void, Never>?

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

    /// Computes the new raw (non-inverted) hold-timing value produced by an
    /// accessibility Increment/Decrement action on the displayed (inverted)
    /// slider position. Increment always moves the *displayed* thumb toward
    /// "Prefer modifiers" (right), matching the visual track direction,
    /// regardless of whether that corresponds to a larger or smaller raw
    /// value. Pulled out as a static, pure function so it can be unit
    /// tested without going through SwiftUI's accessibility runtime.
    nonisolated static func adjustedValue(
        current value: Double,
        direction: AccessibilityAdjustmentDirection,
        range: ClosedRange<Double>,
        step: Double
    ) -> Double {
        let displayedDelta: Double = switch direction {
        case .increment: step
        case .decrement: -step
        @unknown default: 0
        }
        let currentDisplayed = range.upperBound + range.lowerBound - value
        let newDisplayed = min(max(currentDisplayed + displayedDelta, range.lowerBound), range.upperBound)
        return range.upperBound + range.lowerBound - newDisplayed
    }

    var body: some View {
        HStack(spacing: 8) {
            Label("Prefer letters", systemImage: "character.cursor.ibeam")
                .font(.subheadline)
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
            .accessibilityAdjustableAction { direction in
                let newValue = Self.adjustedValue(current: value, direction: direction, range: range, step: step)
                guard newValue != value else { return }
                value = newValue
                onValueChanged?(newValue)

                // Debounce: wait for a pause in Increment/Decrement actions
                // before treating the adjustment as "released", so rapid
                // VoiceOver keypresses coalesce into a single persist/reload
                // instead of one per keypress.
                axReleaseTask?.cancel()
                axReleaseTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    onSliderReleased?()
                }
            }
            .overlay(alignment: .top) {
                if isEditing {
                    GeometryReader { geo in
                        let fraction = (range.upperBound + range.lowerBound - value - range.lowerBound) / (range.upperBound - range.lowerBound)
                        let trackInset: CGFloat = 10
                        let trackWidth = geo.size.width - trackInset * 2
                        let thumbX = trackInset + trackWidth * fraction

                        Text("\(currentValue) ms")
                            .font(.caption.weight(.semibold).width(.condensed))
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .animation(.easeInOut(duration: 0.15), value: isEditing)
    }
}
