import SwiftUI

struct CompactRuleVisualizer: View {
    let behavior: KanataBehavior
    let explanation: String
    let showCodeToggle: Bool
    let onCodeToggle: (() -> Void)?
    @AppStorage("showKanataCode") private var showKanataCode = false

    init(behavior: KanataBehavior, explanation: String, showCodeToggle: Bool = false, onCodeToggle: (() -> Void)? = nil) {
        self.behavior = behavior
        self.explanation = explanation
        self.showCodeToggle = showCodeToggle
        self.onCodeToggle = onCodeToggle
    }

    var body: some View {
        HStack(spacing: 16) {
            // Main visualization first
            switch behavior {
            case .simpleRemap(let from, let toKey):
                CompactSimpleRemapView(from: from, toKey: toKey)

            case .tapHold(let key, let tap, let hold):
                CompactTapHoldView(key: key, tap: tap, hold: hold)

            case .tapDance(let key, let actions):
                CompactTapDanceView(key: key, actions: actions)

            case .sequence(let trigger, let sequence):
                CompactSequenceView(trigger: trigger, sequence: sequence)

            case .combo(let keys, let result):
                CompactComboView(keys: keys, result: result)

            case .layer(let key, let layerName, let mappings):
                CompactLayerView(key: key, layerName: layerName, mappings: mappings)
            }

            // Rule type badge
            Text(behavior.behaviorType)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ruleTypeColor.opacity(0.2))
                .foregroundColor(ruleTypeColor)
                .clipShape(Capsule())

            Spacer()

            // Code toggle button (if enabled) - moved to far right
            if showCodeToggle {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showKanataCode.toggle()
                        onCodeToggle?()
                    }
                }) {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundColor(showKanataCode ? .white : .primary)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .help("Show/hide Kanata configuration code")
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(showKanataCode ?
                              Color.blue :
                              Color.clear)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    showKanataCode ?
                                    Color.clear :
                                    Color.secondary.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: showKanataCode ? Color.blue.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var ruleTypeColor: Color {
        switch behavior {
        case .simpleRemap: return .blue
        case .tapHold: return .orange
        case .tapDance: return .purple
        case .sequence: return .green
        case .combo: return .red
        case .layer: return .cyan
        }
    }
}

// MARK: - Compact Visualizations

struct CompactSimpleRemapView: View {
    let from: String
    let toKey: String

    var body: some View {
        HStack(spacing: 12) {
            CompactKeycap(label: from, style: .source)
            Image(systemName: "arrow.right")
                .font(.title3)
                .foregroundColor(.secondary)
            CompactKeycap(label: toKey, style: .target)
        }
    }
}

struct CompactTapHoldView: View {
    let key: String
    let tap: String
    let hold: String

    var body: some View {
        HStack(spacing: 12) {
            CompactKeycap(label: key, style: .primary)

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("TAP")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    CompactKeycap(label: tap, style: .mini)
                }
                HStack(spacing: 8) {
                    Text("HOLD")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    CompactKeycap(label: hold, style: .mini)
                }
            }
        }
    }
}

struct CompactTapDanceView: View {
    let key: String
    let actions: [TapDanceAction]

    var body: some View {
        HStack(spacing: 12) {
            CompactKeycap(label: key, style: .primary)

            HStack(spacing: 8) {
                ForEach(Array(actions.prefix(3).enumerated()), id: \.offset) { _, action in
                    HStack(spacing: 6) {
                        Text("\(action.tapCount)×")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                        CompactKeycap(label: action.action, style: .mini)
                    }
                }
                if actions.count > 3 {
                    Text("...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct CompactSequenceView: View {
    let trigger: String
    let sequence: [String]

    var body: some View {
        HStack(spacing: 12) {
            CompactKeycap(label: trigger, style: .primary)
            Image(systemName: "arrow.right")
                .font(.title3)
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(Array(sequence.prefix(4).enumerated()), id: \.offset) { _, key in
                    CompactKeycap(label: key, style: .mini)
                }
                if sequence.count > 4 {
                    Text("...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct CompactComboView: View {
    let keys: [String]
    let result: String

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Array(keys.prefix(3).enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Text("+")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    CompactKeycap(label: key, style: .source)
                }
                if keys.count > 3 {
                    Text("...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Image(systemName: "arrow.right")
                .font(.title3)
                .foregroundColor(.secondary)

            CompactKeycap(label: result, style: .target)
        }
    }
}

struct CompactLayerView: View {
    let key: String
    let layerName: String
    let mappings: [String: String]

    var body: some View {
        HStack(spacing: 12) {
            CompactKeycap(label: key, style: .primary)

            VStack(alignment: .leading, spacing: 4) {
                Text(layerName)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.cyan)

                HStack(spacing: 6) {
                    ForEach(Array(mappings.prefix(2)), id: \.key) { key, value in
                        HStack(spacing: 4) {
                            CompactKeycap(label: key, style: .mini)
                            Text("→")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            CompactKeycap(label: value, style: .mini)
                        }
                    }
                    if mappings.count > 2 {
                        Text("+\(mappings.count - 2)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Compact Keycap

struct CompactKeycap: View {
    let label: String
    let style: CompactKeycapStyle

    var body: some View {
        Text(formattedLabel)
            .font(systemFont)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minWidth: minWidth)
            .background(keyColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
    
    private var formattedLabel: String {
        formatKeyLabel(label)
    }
    
    private var isSpecialKey: Bool {
        let formatted = formattedLabel
        return formatted.contains("⌘") || formatted.contains("⌥") || 
               formatted.contains("⌃") || formatted.contains("⇧") || 
               formatted.contains("🌐") || formatted.contains("⇪") ||
               formatted.contains("⎋") || formatted.contains("␣") ||
               formatted.contains("⏎") || formatted.contains("⇥") ||
               formatted.contains("←") || formatted.contains("→") ||
               formatted.contains("↑") || formatted.contains("↓")
    }

    private var systemFont: Font {
        switch style {
        case .mini: 
            return isSpecialKey ? .caption : .caption2
        case .source, .target: 
            return isSpecialKey ? .callout : .body
        case .primary: 
            return isSpecialKey ? .title3 : .title2
        }
    }
    
    private var minWidth: CGFloat {
        switch style {
        case .mini: return 30
        case .source, .target: return 45
        case .primary: return 60
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .mini: return 8
        case .source, .target: return 12
        case .primary: return 16
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .mini: return 4
        case .source, .target: return 6
        case .primary: return 8
        }
    }

    private var keyColor: Color {
        switch style {
        case .source:
            return Color(red: 0.4, green: 0.4, blue: 0.4)
        case .target:
            return Color.blue
        case .primary:
            return Color(red: 0.3, green: 0.3, blue: 0.3)
        case .mini:
            return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }
}

enum CompactKeycapStyle {
    case source, target, primary, mini
}

// MARK: - Hoverable Explanation Button

struct HoverableExplanationButton: View {
    let text: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .underline(isHovering && isEnabled, color: .gray)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isEnabled ? "Click to show Kanata code explanation" : "")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        CompactRuleVisualizer(
            behavior: .simpleRemap(from: "Caps Lock", toKey: "Escape"),
            explanation: "Map Caps Lock to Escape for easier modal editing",
            showCodeToggle: true
        )

        CompactRuleVisualizer(
            behavior: .tapHold(key: "Space", tap: "Space", hold: "Shift"),
            explanation: "Space bar acts as space when tapped, shift when held"
        )

        CompactRuleVisualizer(
            behavior: .tapDance(key: "F", actions: [
                TapDanceAction(tapCount: 1, action: "F", description: ""),
                TapDanceAction(tapCount: 2, action: "Ctrl+F", description: ""),
                TapDanceAction(tapCount: 3, action: "Cmd+F", description: "")
            ]),
            explanation: "F key with multiple tap actions"
        )

        CompactRuleVisualizer(
            behavior: .combo(keys: ["A", "S", "D"], result: "Hello World"),
            explanation: "Chord typing for quick text expansion"
        )
    }
    .padding()
    .frame(width: 500)
}
