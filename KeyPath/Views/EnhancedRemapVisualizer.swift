import SwiftUI

// Helper function to convert key names to Mac symbols
func formatKeyLabel(_ key: String) -> String {
    let lowercased = key.lowercased()

    // Mac modifier symbols
    if lowercased.contains("cmd") || lowercased.contains("command") {
        return key.replacingOccurrences(of: "cmd", with: "⌘", options: .caseInsensitive)
                  .replacingOccurrences(of: "command", with: "⌘", options: .caseInsensitive)
    }
    if lowercased.contains("opt") || lowercased.contains("option") || lowercased.contains("alt") {
        return key.replacingOccurrences(of: "opt", with: "⌥", options: .caseInsensitive)
                  .replacingOccurrences(of: "option", with: "⌥", options: .caseInsensitive)
                  .replacingOccurrences(of: "alt", with: "⌥", options: .caseInsensitive)
    }
    if lowercased.contains("ctrl") || lowercased.contains("control") {
        return key.replacingOccurrences(of: "ctrl", with: "⌃", options: .caseInsensitive)
                  .replacingOccurrences(of: "control", with: "⌃", options: .caseInsensitive)
    }
    if lowercased.contains("shift") {
        return key.replacingOccurrences(of: "shift", with: "⇧", options: .caseInsensitive)
    }

    return key
}

struct EnhancedRemapVisualizer: View {
    let behavior: KanataBehavior
    @State private var animationState: AnimationState = .idle
    @State private var tapCount = 0
    @State private var isPressed = false
    @State private var showSequence = false

    enum AnimationState {
        case idle
        case tapping
        case holding
        case dancing
        case sequencing
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header with behavior type
            HStack {
                Text(behavior.behaviorType)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())

                Spacer()

                Button("Demo") {
                    startDemo()
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
            }

            // Main visualization
            switch behavior {
            case .simpleRemap(let from, let toKey):
                SimpleRemapView(from: from, toKey: toKey, isPressed: isPressed)

            case .tapHold(let key, let tap, let hold):
                TapHoldView(
                    key: key,
                    tap: tap,
                    hold: hold,
                    animationState: animationState,
                    isPressed: isPressed
                )

            case .tapDance(let key, let actions):
                TapDanceView(
                    key: key,
                    actions: actions,
                    tapCount: tapCount,
                    animationState: animationState,
                    isPressed: isPressed
                )

            case .sequence(let trigger, let sequence):
                SequenceView(
                    trigger: trigger,
                    sequence: sequence,
                    showSequence: showSequence,
                    isPressed: isPressed
                )

            case .combo(let keys, let result):
                ComboView(keys: keys, result: result, isPressed: isPressed)

            case .layer(let key, let layerName, let mappings):
                LayerView(
                    key: key,
                    layerName: layerName,
                    mappings: mappings,
                    isPressed: isPressed
                )
            }
        }
        .padding()
    }

    private func startDemo() {
        switch behavior {
        case .simpleRemap:
            // Simple press animation
            withAnimation(.easeInOut(duration: 0.2)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPressed = false
                }
            }

        case .tapHold:
            // Demonstrate tap then hold
            animationState = .tapping
            withAnimation(.easeInOut(duration: 0.15)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isPressed = false
                }
                animationState = .idle
            }

            // Then show hold after a pause
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                animationState = .holding
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPressed = false
                    }
                    animationState = .idle
                }
            }

        case .tapDance:
            // Demonstrate multiple taps
            animationState = .dancing
            tapCount = 0

            for tapIndex in 1...3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(tapIndex) * 0.3) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        tapCount = tapIndex
                        isPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = false
                        }
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                animationState = .idle
                tapCount = 0
            }

        case .sequence:
            // Show sequence expansion
            animationState = .sequencing
            withAnimation(.easeInOut(duration: 0.2)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPressed = false
                    showSequence = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showSequence = false
                }
                animationState = .idle
            }

        case .combo, .layer:
            // Simple press for now
            withAnimation(.easeInOut(duration: 0.2)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPressed = false
                }
            }
        }
    }
}

struct SimpleRemapView: View {
    let from: String
    let toKey: String
    var isPressed: Bool = false

    var body: some View {
        HStack(spacing: 32) {
            EnhancedKeycapView(label: from, style: .source, isPressed: isPressed)

            Image(systemName: "arrow.right")
                .font(.title2)
                .foregroundColor(.secondary)

            EnhancedKeycapView(label: toKey, style: .target, isPressed: isPressed)
        }
    }
}

struct TapHoldView: View {
    let key: String
    let tap: String
    let hold: String
    let animationState: EnhancedRemapVisualizer.AnimationState
    let isPressed: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Main key
            EnhancedKeycapView(
                label: key,
                style: .primary,
                isPressed: isPressed,
                glowColor: animationState == .holding ? .orange : .blue
            )

            // Tap vs Hold actions
            HStack(spacing: 40) {
                VStack(spacing: 8) {
                    Text("TAP")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)

                    EnhancedKeycapView(
                        label: tap,
                        style: .result,
                        isPressed: animationState == .tapping && isPressed,
                        glowColor: .blue
                    )
                    .scaleEffect(animationState == .tapping ? 1.1 : 1.0)
                }

                VStack(spacing: 8) {
                    Text("HOLD")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)

                    EnhancedKeycapView(
                        label: hold,
                        style: .result,
                        isPressed: animationState == .holding && isPressed,
                        glowColor: .orange
                    )
                    .scaleEffect(animationState == .holding ? 1.1 : 1.0)
                }
            }

            // Instructions
            Text("Tap for \(tap) • Hold for \(hold)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct TapDanceView: View {
    let key: String
    let actions: [TapDanceAction]
    let tapCount: Int
    let animationState: EnhancedRemapVisualizer.AnimationState
    let isPressed: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Main key with tap counter
            ZStack {
                EnhancedKeycapView(
                    label: key,
                    style: .primary,
                    isPressed: animationState == .dancing,
                    glowColor: .purple
                )

                if tapCount > 0 {
                    Text("\(tapCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .background(
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 24, height: 24)
                        )
                        .offset(x: 20, y: -20)
                        .scaleEffect(animationState == .dancing ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3), value: tapCount)
                }
            }

            // Tap dance actions
            VStack(spacing: 8) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    HStack {
                        Text("\(action.tapCount)x")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                            .frame(width: 30)

                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        EnhancedKeycapView(
                            label: action.action,
                            style: .mini,
                            isPressed: tapCount == action.tapCount,
                            glowColor: .purple
                        )
                        .scaleEffect(tapCount == action.tapCount ? 1.1 : 1.0)

                        Text(action.description)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color.purple.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

struct SequenceView: View {
    let trigger: String
    let sequence: [String]
    let showSequence: Bool
    let isPressed: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Trigger key
            EnhancedKeycapView(label: trigger, style: .primary, isPressed: isPressed, glowColor: .green)

            Image(systemName: "arrow.down")
                .font(.title2)
                .foregroundColor(.secondary)

            // Sequence expansion
            if showSequence {
                HStack(spacing: 8) {
                    ForEach(Array(sequence.enumerated()), id: \.offset) { index, key in
                        EnhancedKeycapView(
                            label: key,
                            style: .mini,
                            glowColor: .green
                        )
                        .scaleEffect(1.0)
                        .animation(
                            .easeInOut(duration: 0.2)
                            .delay(Double(index) * 0.1),
                            value: showSequence
                        )

                        if index < sequence.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Text("Press to expand sequence")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ComboView: View {
    let keys: [String]
    let result: String
    let isPressed: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Combo keys
            HStack(spacing: 8) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    EnhancedKeycapView(
                        label: key,
                        style: .primary,
                        isPressed: isPressed,
                        glowColor: .red
                    )

                    if index < keys.count - 1 {
                        Text("+")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                }
            }

            Image(systemName: "arrow.down")
                .font(.title2)
                .foregroundColor(.secondary)

            // Result
            EnhancedKeycapView(
                label: result,
                style: .target,
                isPressed: isPressed,
                glowColor: .red
            )
            .scaleEffect(isPressed ? 1.1 : 1.0)

            Text("Press all keys simultaneously")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct LayerView: View {
    let key: String
    let layerName: String
    let mappings: [String: String]
    let isPressed: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Layer key
            EnhancedKeycapView(
                label: key,
                style: .primary,
                isPressed: isPressed,
                glowColor: .cyan
            )

            Text("Layer: \(layerName)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.cyan)

            // Layer mappings preview
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(Array(mappings.prefix(6)), id: \.key) { key, value in
                    HStack(spacing: 4) {
                        EnhancedKeycapView(label: key, style: .mini, glowColor: .cyan)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        EnhancedKeycapView(label: value, style: .mini, glowColor: .cyan)
                    }
                    .scaleEffect(isPressed ? 1.05 : 1.0)
                }
            }
            .padding()
            .background(Color.cyan.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

enum KeycapStyle {
    case source, target, primary, result, mini
}

struct EnhancedKeycapView: View {
    let label: String
    let style: KeycapStyle
    var isPressed: Bool = false
    var glowColor: Color = .blue

    @Environment(\.colorScheme) var colorScheme

    private var size: CGSize {
        switch style {
        case .mini:
            return CGSize(width: 40, height: 30)
        case .source, .target, .result:
            return CGSize(width: max(60, CGFloat(label.count * 10 + 30)), height: 40)
        case .primary:
            return CGSize(width: max(80, CGFloat(label.count * 12 + 40)), height: 50)
        }
    }

    private var fontSize: CGFloat {
        switch style {
        case .mini:
            return 10
        case .source, .target, .result:
            return 14
        case .primary:
            return 16
        }
    }

    private var keyColor: Color {
        switch style {
        case .source:
            return colorScheme == .dark ? Color(red: 0.3, green: 0.3, blue: 0.3) : Color(red: 0.5, green: 0.5, blue: 0.5)
        case .target, .result:
            return glowColor
        case .primary:
            return colorScheme == .dark ? Color(red: 0.2, green: 0.2, blue: 0.2) : Color(red: 0.4, green: 0.4, blue: 0.4)
        case .mini:
            return glowColor.opacity(0.8)
        }
    }

    var body: some View {
        ZStack {
            // Glow effect when pressed
            if isPressed {
                RoundedRectangle(cornerRadius: 8)
                    .fill(glowColor.opacity(0.3))
                    .blur(radius: 8)
                    .scaleEffect(1.2)
            }

            // Shadow
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.3))
                .offset(y: isPressed ? 1 : 3)

            // Main key
            RoundedRectangle(cornerRadius: 8)
                .fill(keyColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )

            // Highlight
            LinearGradient(
                colors: [
                    Color.white.opacity(0.2),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(1)

            // Label
            Text(formatKeyLabel(label))
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size.width, height: size.height)
        .offset(y: isPressed ? 2 : 0)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}
