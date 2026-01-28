import SwiftUI

/// Apple-style "Tap & Hold" card for key behavior configuration.
/// Uses visual keycap illustrations for behavior state selection.
struct TapHoldCardView: View {
    /// The key being configured (display label)
    let keyLabel: String
    /// The key code for live feedback
    let keyCode: UInt16?
    /// Initial slot to show when panel opens
    let initialSlot: BehaviorSlot

    /// Bindings for the behavior intents
    @Binding var tapAction: BehaviorAction
    @Binding var holdAction: BehaviorAction
    @Binding var comboAction: BehaviorAction

    /// Responsiveness preset (maps to timing thresholds)
    @Binding var responsiveness: ResponsivenessLevel
    /// "Use Tap Immediately When I Start Typing"
    @Binding var useTapImmediately: Bool

    /// Which slot is currently selected in the picker
    @State private var selectedSlot: BehaviorSlot = .tap
    /// Live feedback state
    @State private var feedbackState: LiveFeedbackState = .idle

    var body: some View {
        VStack(spacing: 16) {
            // Action configuration for selected slot (no picker - user navigates in/out)
            actionConfigurationSection

            Divider()
                .padding(.horizontal, 8)

            // Responsiveness control
            responsivenessControl

            // Interruption checkbox
            interruptionCheckbox

            Spacer(minLength: 0)
        }
        .onAppear {
            selectedSlot = initialSlot
        }
    }

    /// Which slots have actions configured
    private var configuredStates: Set<BehaviorSlot> {
        var states: Set<BehaviorSlot> = []
        if tapAction != .none { states.insert(.tap) }
        if holdAction != .none { states.insert(.hold) }
        if comboAction != .none { states.insert(.combo) }
        return states
    }

    // MARK: - Action Configuration Section

    private var actionConfigurationSection: some View {
        VStack(spacing: 12) {
            // Header showing what we're configuring
            HStack {
                Text("When I \(selectedSlot.verbPhrase)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(keyLabel.uppercased())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.1))
                    )

                Spacer()
            }
            .padding(.horizontal, 4)

            // Current action display with edit button
            actionDisplayRow

            // Quick action buttons
            quickActionButtons
        }
        .padding(.horizontal, 8)
    }

    private var actionDisplayRow: some View {
        let currentAction = bindingForSlot(selectedSlot).wrappedValue

        return HStack(spacing: 12) {
            // Action icon/preview
            actionIcon(currentAction)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )

            // Action label
            VStack(alignment: .leading, spacing: 2) {
                Text(currentAction.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if let subtitle = currentAction.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Edit button
            Button {
                // TODO: Open action editor
            } label: {
                Text("Edit")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionIcon(_ action: BehaviorAction) -> some View {
        switch action {
        case .none:
            Image(systemName: "minus.circle")
                .font(.title2)
                .foregroundStyle(.tertiary)
        case let .key(label):
            Text(label.uppercased())
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        case let .modifier(symbol):
            Text(symbol)
                .font(.title2)
                .foregroundStyle(.primary)
        case .layer:
            Image(systemName: "square.3.layers.3d")
                .font(.title2)
                .foregroundStyle(.purple)
        case let .app(_, icon):
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
        case let .systemAction(_, iconName):
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(.orange)
        }
    }

    private var quickActionButtons: some View {
        HStack(spacing: 8) {
            quickActionButton(icon: "keyboard", label: "Key") {
                // TODO: Open key picker
            }
            quickActionButton(icon: "command", label: "Modifier") {
                // TODO: Open modifier picker
            }
            quickActionButton(icon: "square.3.layers.3d", label: "Layer") {
                // TODO: Open layer picker
            }
            quickActionButton(icon: "app", label: "App") {
                // TODO: Open app picker
            }
            quickActionButton(icon: "minus.circle", label: "None") {
                bindingForSlot(selectedSlot).wrappedValue = .none
            }
        }
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        let labelIdentifier = label
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
        .accessibilityIdentifier("taphold-quick-\(labelIdentifier)")
    }

    // MARK: - Responsiveness Control

    private var responsivenessControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Responsiveness")
                    .font(.subheadline.weight(.medium))

                Button {
                    // Show tooltip
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Fast favors quick typing. Relaxed favors deliberate holds.")
            }

            Picker("Responsiveness", selection: $responsiveness) {
                Text("Relaxed").tag(ResponsivenessLevel.relaxed)
                Text("Balanced").tag(ResponsivenessLevel.balanced)
                Text("Fast").tag(ResponsivenessLevel.fast)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("tap-hold-responsiveness")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Interruption Checkbox

    private var interruptionCheckbox: some View {
        Toggle(isOn: $useTapImmediately) {
            Text("Use Tap immediately when I start typing")
                .font(.subheadline)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 4)
        .accessibilityIdentifier("tap-hold-use-tap-immediately")
    }

    // MARK: - Helpers

    private func bindingForSlot(_ slot: BehaviorSlot) -> Binding<BehaviorAction> {
        switch slot {
        case .tap: $tapAction
        case .hold: $holdAction
        case .combo: $comboAction
        }
    }
}

// MARK: - Supporting Types

/// The four behavior intents (80/20 mode)
enum BehaviorSlot: String, Identifiable, CaseIterable {
    case tap
    case hold
    case combo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tap: "Tap"
        case .hold: "Hold"
        case .combo: "Combo"
        }
    }

    /// Shorter label for compact display
    var shortLabel: String {
        switch self {
        case .tap: "Tap"
        case .hold: "Hold"
        case .combo: "Combo"
        }
    }

    var verbPhrase: String {
        switch self {
        case .tap: "tap"
        case .hold: "hold"
        case .combo: "press together with"
        }
    }

    var icon: String {
        switch self {
        case .tap: "hand.tap"
        case .hold: "hand.point.down.fill"
        case .combo: "rectangle.on.rectangle"
        }
    }
}

/// What a behavior slot does
enum BehaviorAction: Equatable {
    case none
    case key(String)
    case modifier(String) // e.g., "⌘", "⌥"
    case layer(String)
    case app(name: String, icon: NSImage?)
    case systemAction(name: String, icon: String)

    var displayName: String {
        switch self {
        case .none: "Not configured"
        case let .key(k): "Key: \(k.uppercased())"
        case let .modifier(m): "Modifier: \(m)"
        case let .layer(l): "Layer: \(l)"
        case let .app(n, _): "Launch: \(n)"
        case let .systemAction(n, _): n
        }
    }

    var subtitle: String? {
        switch self {
        case .none: "Tap to set an action"
        case .key: nil
        case .modifier: nil
        case .layer: "Switch to layer"
        case .app: "Open application"
        case .systemAction: "System action"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .none: "not configured"
        case let .key(k): "key \(k)"
        case let .modifier(m): "modifier \(m)"
        case let .layer(l): "layer \(l)"
        case let .app(n, _): "launch \(n)"
        case let .systemAction(n, _): "\(n)"
        }
    }

    static func == (lhs: BehaviorAction, rhs: BehaviorAction) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case let (.key(a), .key(b)): a == b
        case let (.modifier(a), .modifier(b)): a == b
        case let (.layer(a), .layer(b)): a == b
        case let (.app(a, _), .app(b, _)): a == b
        case let (.systemAction(a, _), .systemAction(b, _)): a == b
        default: false
        }
    }
}

/// Responsiveness presets (maps to timing thresholds)
enum ResponsivenessLevel: String, CaseIterable {
    case relaxed
    case balanced
    case fast

    /// Tapping term in milliseconds
    var tappingTerm: Int {
        switch self {
        case .relaxed: 300
        case .balanced: 200
        case .fast: 150
        }
    }

    /// Hold term in milliseconds
    var holdTerm: Int {
        switch self {
        case .relaxed: 250
        case .balanced: 200
        case .fast: 150
        }
    }
}

/// Live feedback state for the key preview
enum LiveFeedbackState: Equatable {
    case idle
    case holding(progress: CGFloat) // 0.0 to 1.0
    case tapped(count: Int)
}

// MARK: - Preview

#if DEBUG
    #Preview("Tap & Hold Card") {
        struct PreviewWrapper: View {
            @State var tap: BehaviorAction = .key("a")
            @State var hold: BehaviorAction = .modifier("⌘")
            @State var combo: BehaviorAction = .layer("Nav")
            @State var responsiveness: ResponsivenessLevel = .balanced
            @State var useTapImmediately = true

            var body: some View {
                TapHoldCardView(
                    keyLabel: "A",
                    keyCode: 0,
                    initialSlot: .tap,
                    tapAction: $tap,
                    holdAction: $hold,
                    comboAction: $combo,
                    responsiveness: $responsiveness,
                    useTapImmediately: $useTapImmediately
                )
                .frame(width: 300, height: 480)
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }

        return PreviewWrapper()
    }
#endif
