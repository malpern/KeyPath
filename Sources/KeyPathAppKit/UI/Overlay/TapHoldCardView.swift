import SwiftUI

/// Apple-style "Tap & Hold" card for key behavior configuration.
/// Implements the 80/20 design: four intents, one responsiveness control, live feedback.
struct TapHoldCardView: View {
    /// The key being configured (display label)
    let keyLabel: String
    /// The key code for live feedback
    let keyCode: UInt16?

    /// Bindings for the four behavior intents
    @Binding var tapAction: BehaviorAction
    @Binding var holdAction: BehaviorAction
    @Binding var doubleTapAction: BehaviorAction
    @Binding var tapHoldAction: BehaviorAction

    /// Responsiveness preset (maps to timing thresholds)
    @Binding var responsiveness: ResponsivenessLevel
    /// "Use Tap Immediately When I Start Typing"
    @Binding var useTapImmediately: Bool

    /// Which slot is being edited (opens sheet)
    @State private var editingSlot: BehaviorSlot?
    /// Live feedback state
    @State private var feedbackState: LiveFeedbackState = .idle

    var body: some View {
        VStack(spacing: 16) {
            // Header with key preview
            keyPreviewHeader

            // Four behavior slots
            behaviorSlots

            Divider()
                .padding(.horizontal, 8)

            // Responsiveness control
            responsivenessControl

            // Interruption checkbox
            interruptionCheckbox

            Spacer(minLength: 0)
        }
        .sheet(item: $editingSlot) { slot in
            BehaviorSlotEditor(
                slot: slot,
                action: bindingForSlot(slot),
                onDismiss: { editingSlot = nil }
            )
        }
    }

    // MARK: - Key Preview Header

    private var keyPreviewHeader: some View {
        VStack(spacing: 8) {
            Text("When I press")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Large keycap preview with live feedback ring
            ZStack {
                // Feedback ring (fills during hold)
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 3)
                    .frame(width: 72, height: 72)

                if case .holding(let progress) = feedbackState {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                }

                // Keycap
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                    .overlay(
                        Text(keyLabel.uppercased())
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)
                    )

                // Tap flash badge
                if case .tapped(let count) = feedbackState {
                    tapBadge(count: count)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: feedbackState)
        }
        .padding(.top, 8)
    }

    private func tapBadge(count: Int) -> some View {
        Text(count == 1 ? "Tap" : "×\(count)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.accentColor))
            .offset(x: 32, y: -24)
    }

    // MARK: - Behavior Slots

    private var behaviorSlots: some View {
        VStack(spacing: 2) {
            behaviorSlotRow(.tap, action: tapAction)
            behaviorSlotRow(.hold, action: holdAction)
            behaviorSlotRow(.doubleTap, action: doubleTapAction)
            behaviorSlotRow(.tapHold, action: tapHoldAction)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func behaviorSlotRow(_ slot: BehaviorSlot, action: BehaviorAction) -> some View {
        Button {
            editingSlot = slot
        } label: {
            HStack(spacing: 12) {
                // Slot label
                Text(slot.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(width: 90, alignment: .leading)

                // Arrow
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                // Action preview
                actionPreview(action)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(SlotButtonStyle())
        .accessibilityIdentifier("tap-hold-slot-\(slot.rawValue)")
        .accessibilityLabel("\(slot.label): \(action.accessibilityDescription)")
    }

    @ViewBuilder
    private func actionPreview(_ action: BehaviorAction) -> some View {
        switch action {
        case .none:
            Text("Not set")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .italic()

        case .key(let label):
            HStack(spacing: 4) {
                miniKeycap(label)
            }

        case .modifier(let symbol):
            Text(symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

        case .layer(let name):
            HStack(spacing: 4) {
                Image(systemName: "square.3.layers.3d")
                    .font(.caption)
                Text(name)
                    .font(.subheadline)
            }
            .foregroundStyle(.purple)

        case .app(let name, let icon):
            HStack(spacing: 6) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)

        case .systemAction(let name, let icon):
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(name)
                    .font(.subheadline)
            }
            .foregroundStyle(.orange)
        }
    }

    private func miniKeycap(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
    }

    // MARK: - Responsiveness Control

    private var responsivenessControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Responsiveness")
                    .font(.subheadline.weight(.medium))

                // Info button
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
        case .doubleTap: $doubleTapAction
        case .tapHold: $tapHoldAction
        }
    }
}

// MARK: - Supporting Types

/// The four behavior intents (80/20 mode)
enum BehaviorSlot: String, Identifiable, CaseIterable {
    case tap
    case hold
    case doubleTap
    case tapHold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tap: "Tap"
        case .hold: "Hold"
        case .doubleTap: "Double Tap"
        case .tapHold: "Tap + Hold"
        }
    }

    var icon: String {
        switch self {
        case .tap: "hand.tap"
        case .hold: "hand.point.down.fill"
        case .doubleTap: "hand.tap.fill"
        case .tapHold: "rectangle.compress.vertical"
        }
    }
}

/// What a behavior slot does
enum BehaviorAction: Equatable {
    case none
    case key(String)
    case modifier(String)  // e.g., "⌘", "⌥"
    case layer(String)
    case app(name: String, icon: NSImage?)
    case systemAction(name: String, icon: String)

    var accessibilityDescription: String {
        switch self {
        case .none: "not configured"
        case .key(let k): "key \(k)"
        case .modifier(let m): "modifier \(m)"
        case .layer(let l): "layer \(l)"
        case .app(let n, _): "launch \(n)"
        case .systemAction(let n, _): "\(n)"
        }
    }

    static func == (lhs: BehaviorAction, rhs: BehaviorAction) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case (.key(let a), .key(let b)): a == b
        case (.modifier(let a), .modifier(let b)): a == b
        case (.layer(let a), .layer(let b)): a == b
        case (.app(let a, _), .app(let b, _)): a == b
        case (.systemAction(let a, _), .systemAction(let b, _)): a == b
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
    case holding(progress: CGFloat)  // 0.0 to 1.0
    case tapped(count: Int)
}

// MARK: - Slot Button Style

private struct SlotButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(Color.primary.opacity(
                        configuration.isPressed ? 0.08 : (isHovering ? 0.04 : 0)
                    ))
            )
            .onHover { isHovering = $0 }
    }
}

// MARK: - Behavior Slot Editor Sheet

/// Sheet for editing a behavior slot's action
struct BehaviorSlotEditor: View {
    let slot: BehaviorSlot
    @Binding var action: BehaviorAction
    let onDismiss: () -> Void

    @State private var selectedType: ActionType = .key
    @State private var keyInput: String = ""
    @State private var selectedModifier: String = ""
    @State private var selectedLayer: String = ""
    @State private var isRecording = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(slot.label)
                    .font(.headline)

                Spacer()

                Button("Done") {
                    applyAction()
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding()

            Divider()

            // Action type picker
            Picker("Action Type", selection: $selectedType) {
                Label("Key", systemImage: "keyboard").tag(ActionType.key)
                Label("Modifier", systemImage: "command").tag(ActionType.modifier)
                Label("Layer", systemImage: "square.3.layers.3d").tag(ActionType.layer)
                Label("App", systemImage: "app").tag(ActionType.app)
                Label("System", systemImage: "gearshape").tag(ActionType.system)
                Label("None", systemImage: "minus.circle").tag(ActionType.none)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            // Content based on type
            ScrollView {
                actionTypeContent
                    .padding()
            }
        }
        .frame(width: 320, height: 400)
        .onAppear {
            loadCurrentAction()
        }
    }

    @ViewBuilder
    private var actionTypeContent: some View {
        switch selectedType {
        case .key:
            keyInputContent
        case .modifier:
            modifierPickerContent
        case .layer:
            layerPickerContent
        case .app:
            Text("App picker coming soon")
                .foregroundStyle(.secondary)
        case .system:
            Text("System action picker coming soon")
                .foregroundStyle(.secondary)
        case .none:
            Text("This slot will do nothing")
                .foregroundStyle(.secondary)
        }
    }

    private var keyInputContent: some View {
        VStack(spacing: 16) {
            Text("Press a key or type it:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Large keycap for recording
            Button {
                isRecording.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isRecording ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.2), lineWidth: 2)
                    )
                    .overlay(
                        Group {
                            if keyInput.isEmpty {
                                Image(systemName: isRecording ? "keyboard" : "plus")
                                    .font(.title)
                                    .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
                            } else {
                                Text(keyInput.uppercased())
                                    .font(.system(size: 32, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary)
                            }
                        }
                    )
            }
            .buttonStyle(.plain)

            if isRecording {
                Text("Press any key...")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var modifierPickerContent: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
            ForEach(["⌘", "⌥", "⌃", "⇧", "🌐"], id: \.self) { mod in
                Button {
                    selectedModifier = mod
                } label: {
                    Text(mod)
                        .font(.title)
                        .frame(width: 56, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedModifier == mod ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selectedModifier == mod ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var layerPickerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch to layer:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // TODO: Load actual layers
            ForEach(["Nav", "Symbols", "Numbers", "Function"], id: \.self) { layer in
                Button {
                    selectedLayer = layer
                } label: {
                    HStack {
                        Image(systemName: "square.3.layers.3d")
                        Text(layer)
                        Spacer()
                        if selectedLayer == layer {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedLayer == layer ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadCurrentAction() {
        switch action {
        case .none:
            selectedType = .none
        case .key(let k):
            selectedType = .key
            keyInput = k
        case .modifier(let m):
            selectedType = .modifier
            selectedModifier = m
        case .layer(let l):
            selectedType = .layer
            selectedLayer = l
        case .app:
            selectedType = .app
        case .systemAction:
            selectedType = .system
        }
    }

    private func applyAction() {
        switch selectedType {
        case .key:
            action = keyInput.isEmpty ? .none : .key(keyInput)
        case .modifier:
            action = selectedModifier.isEmpty ? .none : .modifier(selectedModifier)
        case .layer:
            action = selectedLayer.isEmpty ? .none : .layer(selectedLayer)
        case .app:
            break // TODO
        case .system:
            break // TODO
        case .none:
            action = .none
        }
    }

    enum ActionType: String, CaseIterable {
        case key, modifier, layer, app, system, none
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Tap & Hold Card") {
    struct PreviewWrapper: View {
        @State var tap: BehaviorAction = .key("a")
        @State var hold: BehaviorAction = .modifier("⌘")
        @State var doubleTap: BehaviorAction = .none
        @State var tapHold: BehaviorAction = .layer("Nav")
        @State var responsiveness: ResponsivenessLevel = .balanced
        @State var useTapImmediately = true

        var body: some View {
            TapHoldCardView(
                keyLabel: "A",
                keyCode: 0,
                tapAction: $tap,
                holdAction: $hold,
                doubleTapAction: $doubleTap,
                tapHoldAction: $tapHold,
                responsiveness: $responsiveness,
                useTapImmediately: $useTapImmediately
            )
            .frame(width: 280, height: 450)
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    return PreviewWrapper()
}
#endif
