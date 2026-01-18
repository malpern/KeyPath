import SwiftUI

/// A horizontal picker showing the four behavior states with keycap illustrations.
/// Styled after Apple's dark UI with glass-like appearance and blue selection glow.
struct BehaviorStatePicker: View {
    @Binding var selectedState: BehaviorSlot

    /// Whether each state has a configured action
    var configuredStates: Set<BehaviorSlot> = []

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BehaviorSlot.allCases) { slot in
                behaviorStateCell(slot)

                // Divider between cells (not after last)
                if slot != BehaviorSlot.allCases.last {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func behaviorStateCell(_ slot: BehaviorSlot) -> some View {
        let isSelected = selectedState == slot
        let isConfigured = configuredStates.contains(slot)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedState = slot
            }
        } label: {
            VStack(spacing: 8) {
                // Keycap illustration
                keycapIllustration(for: slot, isSelected: isSelected)
                    .frame(height: 50)

                // Label
                Text(slot.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                Group {
                    if isSelected {
                        // Selected state blue glow background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.blue.opacity(0.4),
                                        Color.blue.opacity(0.2)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("behavior-picker-\(slot.rawValue)")
        .accessibilityLabel("\(slot.label)\(isConfigured ? ", configured" : "")")
    }

    @ViewBuilder
    private func keycapIllustration(for slot: BehaviorSlot, isSelected: Bool) -> some View {
        switch slot {
        case .tap:
            TapKeycapView(showWaves: true, isSelected: isSelected)
        case .hold:
            HoldKeycapView(isSelected: isSelected)
        case .doubleTap:
            DoubleTapKeycapView(isSelected: isSelected)
        case .tapHold:
            TapHoldKeycapView(isSelected: isSelected)
        }
    }
}

// MARK: - Keycap Illustrations

/// Single keycap with tap waves
private struct TapKeycapView: View {
    var showWaves: Bool = true
    var isSelected: Bool = false

    var body: some View {
        ZStack {
            // Glow under keycap when selected
            if isSelected {
                Ellipse()
                    .fill(Color.blue.opacity(0.4))
                    .frame(width: 40, height: 12)
                    .blur(radius: 8)
                    .offset(y: 18)
            }

            // Shadow
            Ellipse()
                .fill(Color.black.opacity(0.5))
                .frame(width: 32, height: 8)
                .offset(y: 16)
                .blur(radius: 3)

            // Keycap
            KeycapShape()
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(white: 0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 28, height: 24)
                .overlay(
                    KeycapShape()
                        .stroke(Color.black.opacity(0.3), lineWidth: 1.5)
                )

            // Tap waves
            if showWaves {
                TapWavesView()
                    .offset(y: -20)
            }
        }
    }
}

/// Single keycap pressed down (hold state)
private struct HoldKeycapView: View {
    var isSelected: Bool = false

    var body: some View {
        ZStack {
            // Larger shadow when pressed
            if isSelected {
                Ellipse()
                    .fill(Color.blue.opacity(0.4))
                    .frame(width: 44, height: 14)
                    .blur(radius: 10)
                    .offset(y: 16)
            }

            // Pressed shadow (wider, closer)
            Ellipse()
                .fill(Color.black.opacity(0.6))
                .frame(width: 36, height: 10)
                .offset(y: 14)
                .blur(radius: 4)

            // Keycap (slightly lower, compressed)
            KeycapShape()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.9), Color(white: 0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 28, height: 22)
                .offset(y: 2)
                .overlay(
                    KeycapShape()
                        .stroke(Color.black.opacity(0.35), lineWidth: 1.5)
                        .offset(y: 2)
                )
        }
    }
}

/// Two keycaps for double tap
private struct DoubleTapKeycapView: View {
    var isSelected: Bool = false

    var body: some View {
        ZStack {
            // Glow under keycaps when selected
            if isSelected {
                Ellipse()
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 56, height: 16)
                    .blur(radius: 10)
                    .offset(y: 16)
            }

            // Back keycap (slightly offset)
            Group {
                Ellipse()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 28, height: 7)
                    .offset(x: 8, y: 14)
                    .blur(radius: 2)

                KeycapShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.95), Color(white: 0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 24, height: 20)
                    .offset(x: 8, y: -2)
                    .overlay(
                        KeycapShape()
                            .stroke(Color.black.opacity(0.25), lineWidth: 1.2)
                            .offset(x: 8, y: -2)
                    )
            }

            // Front keycap
            Group {
                Ellipse()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 28, height: 7)
                    .offset(x: -6, y: 16)
                    .blur(radius: 2)

                KeycapShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 24, height: 20)
                    .offset(x: -6)
                    .overlay(
                        KeycapShape()
                            .stroke(Color.black.opacity(0.3), lineWidth: 1.2)
                            .offset(x: -6)
                    )
            }

            // Tap waves on front keycap
            TapWavesView()
                .scaleEffect(0.85)
                .offset(x: -6, y: -18)
        }
    }
}

/// Two keycaps with arrow for tap then hold
private struct TapHoldKeycapView: View {
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            // First keycap with waves (tap)
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 22, height: 6)
                    .offset(y: 12)
                    .blur(radius: 2)

                KeycapShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 20, height: 17)
                    .overlay(
                        KeycapShape()
                            .stroke(Color.black.opacity(0.3), lineWidth: 1)
                    )

                TapWavesView()
                    .scaleEffect(0.7)
                    .offset(y: -14)
            }

            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))

            // Second keycap pressed (hold)
            ZStack {
                if isSelected {
                    Ellipse()
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: 28, height: 10)
                        .blur(radius: 6)
                        .offset(y: 12)
                }

                Ellipse()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 24, height: 7)
                    .offset(y: 11)
                    .blur(radius: 2)

                KeycapShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.9), Color(white: 0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 20, height: 16)
                    .offset(y: 1)
                    .overlay(
                        KeycapShape()
                            .stroke(Color.black.opacity(0.35), lineWidth: 1)
                            .offset(y: 1)
                    )
            }
        }
    }
}

/// Blue tap indicator waves
private struct TapWavesView: View {
    var body: some View {
        VStack(spacing: 2) {
            // Outer arc
            Arc(startAngle: .degrees(200), endAngle: .degrees(340))
                .stroke(Color.cyan, lineWidth: 2)
                .frame(width: 20, height: 8)

            // Inner arc
            Arc(startAngle: .degrees(210), endAngle: .degrees(330))
                .stroke(Color.cyan, lineWidth: 2)
                .frame(width: 14, height: 6)
        }
    }
}

/// Custom keycap shape (rounded rectangle with 3D perspective)
private struct KeycapShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Use RoundedRectangle for simplicity
        RoundedRectangle(cornerRadius: 4).path(in: rect)
    }
}

/// Arc shape for tap waves
private struct Arc: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Behavior State Picker") {
    struct PreviewWrapper: View {
        @State var selected: BehaviorSlot = .doubleTap

        var body: some View {
            VStack(spacing: 40) {
                BehaviorStatePicker(
                    selectedState: $selected,
                    configuredStates: [.tap, .hold]
                )
                .frame(width: 340)

                Text("Selected: \(selected.label)")
                    .foregroundStyle(.white)
            }
            .padding(40)
            .background(Color.black)
        }
    }

    return PreviewWrapper()
}

#Preview("Behavior State Picker - Light") {
    struct PreviewWrapper: View {
        @State var selected: BehaviorSlot = .tap

        var body: some View {
            BehaviorStatePicker(
                selectedState: $selected,
                configuredStates: []
            )
            .frame(width: 340)
            .padding(40)
            .background(Color(white: 0.15))
        }
    }

    return PreviewWrapper()
}
#endif
