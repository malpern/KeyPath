import KeyPathCore
import SwiftUI

struct CustomRuleEditorView: View {
    enum Mode {
        case create
        case edit
    }

    @Environment(\.dismiss) private var dismiss
    @State private var customName: String
    @State private var input: String
    @State private var output: String
    @State private var isEnabled: Bool
    @State private var behavior: MappingBehavior?
    @State private var showAdvanced: Bool = false
    @State private var isRecordingInput: Bool = false
    @State private var isRecordingOutput: Bool = false
    @State private var validationError: String?
    @State private var showDeleteConfirmation = false

    // Advanced action states
    @State private var holdAction: String = ""
    @State private var doubleTapAction: String = ""
    @State private var tapHoldAction: String = ""
    @State private var tappingTerm: Int = 200
    @State private var isRecordingHold: Bool = false
    @State private var isRecordingDoubleTap: Bool = false
    @State private var isRecordingTapHold: Bool = false

    private let existingRule: CustomRule?
    private let existingRules: [CustomRule]
    private let mode: Mode
    let onSave: (CustomRule) -> Void
    let onDelete: ((CustomRule) -> Void)?

    // Consistent sizing
    private let fieldHeight: CGFloat = 44
    private let buttonSize: CGFloat = 44
    private let cornerRadius: CGFloat = 8
    private let spacing: CGFloat = 16

    init(
        rule: CustomRule?,
        existingRules: [CustomRule] = [],
        onSave: @escaping (CustomRule) -> Void,
        onDelete: ((CustomRule) -> Void)? = nil
    ) {
        existingRule = rule
        self.existingRules = existingRules
        self.onSave = onSave
        self.onDelete = onDelete
        if let rule {
            _customName = State(initialValue: rule.title)
            _input = State(initialValue: rule.input)
            _output = State(initialValue: rule.output)
            _isEnabled = State(initialValue: rule.isEnabled)
            _behavior = State(initialValue: rule.behavior)
            _showAdvanced = State(initialValue: rule.behavior != nil)
            mode = .edit
        } else {
            _customName = State(initialValue: "")
            _input = State(initialValue: "")
            _output = State(initialValue: "")
            _isEnabled = State(initialValue: true)
            _behavior = State(initialValue: nil)
            _showAdvanced = State(initialValue: false)
            mode = .create
        }
    }

    private var displayName: String {
        if !customName.isEmpty {
            return customName
        } else if !input.isEmpty || !output.isEmpty {
            let inputDisplay = input.isEmpty ? "?" : KeyDisplayName.display(for: input)
            let outputDisplay = output.isEmpty ? "?" : KeyDisplayName.display(for: output)
            return "\(inputDisplay) → \(outputDisplay)"
        } else {
            return "New Rule"
        }
    }

    private var canSave: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header - simple title, no divider
            HStack {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)

                Spacer()

                if mode == .edit, onDelete != nil {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete rule")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)

            // Content
            ScrollView {
                VStack(spacing: spacing) {
                    // Input Key
                    keyInputField(
                        label: "Input Key",
                        key: $input,
                        isRecording: $isRecordingInput
                    )

                    // Output Key
                    keyInputField(
                        label: "Output Key",
                        key: $output,
                        isRecording: $isRecordingOutput
                    )

                    // Advanced options - using native Toggle for reveal
                    advancedSection

                    // Validation error
                    if let error = validationError {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer buttons
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 460, height: showAdvanced ? 540 : 340)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Delete Rule?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let rule = existingRule {
                    onDelete?(rule)
                }
                dismiss()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear {
            initializeFromBehavior()
        }
    }

    // MARK: - Key Input Field

    @ViewBuilder
    private func keyInputField(
        label: String,
        key: Binding<String>,
        isRecording: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                // Input field
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(NSColor.controlBackgroundColor))

                    if isRecording.wrappedValue {
                        Text("Press a key...")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                    } else if key.wrappedValue.isEmpty {
                        Text("Click to record")
                            .font(.body)
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.horizontal, 16)
                    } else {
                        Text(KeyDisplayName.display(for: key.wrappedValue))
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                    }
                }
                .frame(height: fieldHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isRecording.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.2),
                            lineWidth: isRecording.wrappedValue ? 2 : 1
                        )
                )
                .onTapGesture {
                    if !isRecording.wrappedValue, !anyOtherRecording(except: isRecording) {
                        isRecording.wrappedValue = true
                        startKeyCapture(into: key, isRecording: isRecording)
                    }
                }

                // Record button
                Button {
                    if isRecording.wrappedValue {
                        isRecording.wrappedValue = false
                    } else if !anyOtherRecording(except: isRecording) {
                        isRecording.wrappedValue = true
                        startKeyCapture(into: key, isRecording: isRecording)
                    }
                } label: {
                    Image(systemName: isRecording.wrappedValue ? "stop.fill" : "record.circle")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(isRecording.wrappedValue ? Color.red : Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func anyOtherRecording(except current: Binding<Bool>) -> Bool {
        let allRecordings = [
            $isRecordingInput, $isRecordingOutput,
            $isRecordingHold, $isRecordingDoubleTap, $isRecordingTapHold
        ]
        return allRecordings.contains { $0.wrappedValue && $0.wrappedValue != current.wrappedValue }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: spacing) {
            // Toggle for advanced mode - more Mac-native
            Toggle(isOn: $showAdvanced) {
                Text("Hold, Double Tap, ...")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .toggleStyle(.switch)
            .onChange(of: showAdvanced) { _, isExpanded in
                if !isExpanded {
                    behavior = nil
                    holdAction = ""
                    doubleTapAction = ""
                    tapHoldAction = ""
                    tappingTerm = 200
                }
            }

            if showAdvanced {
                VStack(spacing: spacing) {
                    // Hold action
                    actionField(
                        label: "On Hold",
                        key: $holdAction,
                        isRecording: $isRecordingHold
                    )

                    // Double tap action
                    actionField(
                        label: "Double Tap",
                        key: $doubleTapAction,
                        isRecording: $isRecordingDoubleTap
                    )

                    // Tap + hold action
                    actionField(
                        label: "Tap + Hold",
                        key: $tapHoldAction,
                        isRecording: $isRecordingTapHold
                    )

                    // Tapping term - simple text field
                    HStack(spacing: 12) {
                        Text("Timing (ms)")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(width: 100, alignment: .leading)

                        TextField("200", value: $tappingTerm, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: tappingTerm) { _, _ in syncBehavior() }

                        Spacer()

                        // Reset button
                        Button("Reset") {
                            resetAdvanced()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func actionField(
        label: String,
        key: Binding<String>,
        isRecording: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                // Input field - same size as main fields
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(NSColor.controlBackgroundColor))

                    if isRecording.wrappedValue {
                        Text("Press a key...")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                    } else if key.wrappedValue.isEmpty {
                        Text("Optional")
                            .font(.body)
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(.horizontal, 16)
                    } else {
                        Text(KeyDisplayName.display(for: key.wrappedValue))
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                    }
                }
                .frame(height: fieldHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isRecording.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.2),
                            lineWidth: isRecording.wrappedValue ? 2 : 1
                        )
                )
                .onTapGesture {
                    if !isRecording.wrappedValue, !anyOtherRecording(except: isRecording) {
                        isRecording.wrappedValue = true
                        startKeyCapture(into: key, isRecording: isRecording)
                    }
                }

                // Record button - same size as main buttons
                Button {
                    if isRecording.wrappedValue {
                        isRecording.wrappedValue = false
                    } else if !anyOtherRecording(except: isRecording) {
                        isRecording.wrappedValue = true
                        startKeyCapture(into: key, isRecording: isRecording)
                    }
                } label: {
                    Image(systemName: isRecording.wrappedValue ? "stop.fill" : "record.circle")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(isRecording.wrappedValue ? Color.red : Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resetAdvanced() {
        holdAction = ""
        doubleTapAction = ""
        tapHoldAction = ""
        tappingTerm = 200
        syncBehavior()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(mode == .create ? "Add" : "Save") {
                saveRule()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
    }

    // MARK: - Key Capture

    private func startKeyCapture(into key: Binding<String>, isRecording: Binding<Bool>) {
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording
            if event.keyCode == 53 {
                isRecording.wrappedValue = false
                if let m = monitor {
                    NSEvent.removeMonitor(m)
                }
                return nil
            }

            let keyName = Self.keyNameFromEvent(event)
            key.wrappedValue = keyName
            isRecording.wrappedValue = false
            syncBehavior()
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
            return nil
        }

        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if isRecording.wrappedValue {
                isRecording.wrappedValue = false
                if let m = monitor { NSEvent.removeMonitor(m) }
            }
        }
    }

    private static func keyNameFromEvent(_ event: NSEvent) -> String {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags

        var prefix = ""
        if modifiers.contains(.command) { prefix += "M-" }
        if modifiers.contains(.control) { prefix += "C-" }
        if modifiers.contains(.option) { prefix += "A-" }
        if modifiers.contains(.shift) { prefix += "S-" }

        let keyName = switch keyCode {
        case 0: "a"
        case 1: "s"
        case 2: "d"
        case 3: "f"
        case 4: "h"
        case 5: "g"
        case 6: "z"
        case 7: "x"
        case 8: "c"
        case 9: "v"
        case 11: "b"
        case 12: "q"
        case 13: "w"
        case 14: "e"
        case 15: "r"
        case 16: "y"
        case 17: "t"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "="
        case 25: "9"
        case 26: "7"
        case 27: "-"
        case 28: "8"
        case 29: "0"
        case 30: "]"
        case 31: "o"
        case 32: "u"
        case 33: "["
        case 34: "i"
        case 35: "p"
        case 36: "ret"
        case 37: "l"
        case 38: "j"
        case 39: "'"
        case 40: "k"
        case 41: ";"
        case 42: "\\"
        case 43: ","
        case 44: "/"
        case 45: "n"
        case 46: "m"
        case 47: "."
        case 48: "tab"
        case 49: "spc"
        case 50: "`"
        case 51: "bspc"
        case 53: "esc"
        case 55: "lmet"
        case 56: "lsft"
        case 57: "caps"
        case 58: "lalt"
        case 59: "lctl"
        case 60: "rsft"
        case 61: "ralt"
        case 62: "rctl"
        case 63: "fn"
        case 96: "f5"
        case 97: "f6"
        case 98: "f7"
        case 99: "f3"
        case 100: "f8"
        case 101: "f9"
        case 103: "f11"
        case 105: "f13"
        case 107: "f14"
        case 109: "f10"
        case 111: "f12"
        case 113: "f15"
        case 118: "f4"
        case 119: "end"
        case 120: "f2"
        case 121: "pgdn"
        case 122: "f1"
        case 123: "left"
        case 124: "right"
        case 125: "down"
        case 126: "up"
        default: "k\(keyCode)"
        }

        return prefix + keyName
    }

    // MARK: - Behavior Sync

    private func initializeFromBehavior() {
        guard let behavior else { return }

        switch behavior {
        case let .dualRole(dr):
            // tapAction is the output key, holdAction is stored
            holdAction = dr.holdAction
            tappingTerm = dr.tapTimeout

        case let .tapDance(td):
            tappingTerm = td.windowMs
            // First step is tap (same as output), rest are other actions
            for (index, step) in td.steps.enumerated() {
                switch index {
                case 0: break // Tap action = output, already set
                case 1: doubleTapAction = step.action
                case 2: holdAction = step.action
                case 3: tapHoldAction = step.action
                default: break
                }
            }
        }
    }

    private func syncBehavior() {
        guard showAdvanced else {
            behavior = nil
            return
        }

        // Tap action is always the output key
        let hasTap = !output.isEmpty
        let hasHold = !holdAction.isEmpty
        let hasDoubleTap = !doubleTapAction.isEmpty
        let hasTapHold = !tapHoldAction.isEmpty

        if !hasHold, !hasDoubleTap, !hasTapHold {
            behavior = nil
            return
        }

        // If only hold action, use dual-role (tap = output, hold = holdAction)
        if hasHold, !hasDoubleTap, !hasTapHold {
            behavior = .dualRole(DualRoleBehavior(
                tapAction: output,
                holdAction: holdAction,
                tapTimeout: tappingTerm,
                holdTimeout: tappingTerm,
                activateHoldOnOtherKey: false,
                quickTap: false
            ))
            return
        }

        // Otherwise use tap-dance
        var steps: [TapDanceStep] = []
        if hasTap {
            steps.append(TapDanceStep(label: "Single tap", action: output))
        }
        if hasDoubleTap {
            steps.append(TapDanceStep(label: "Double tap", action: doubleTapAction))
        }
        if hasHold {
            steps.append(TapDanceStep(label: "Hold", action: holdAction))
        }
        if hasTapHold {
            steps.append(TapDanceStep(label: "Tap + hold", action: tapHoldAction))
        }

        if !steps.isEmpty {
            behavior = .tapDance(TapDanceBehavior(
                windowMs: tappingTerm,
                steps: steps
            ))
        } else {
            behavior = nil
        }
    }

    // MARK: - Save

    private func saveRule() {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedInput.isEmpty {
            validationError = "Input key required"
            return
        }
        if trimmedOutput.isEmpty {
            validationError = "Output key required"
            return
        }

        syncBehavior()

        let rule = CustomRule(
            id: existingRule?.id ?? UUID(),
            title: customName,
            input: trimmedInput,
            output: trimmedOutput,
            isEnabled: isEnabled,
            notes: nil,
            createdAt: existingRule?.createdAt ?? Date(),
            behavior: behavior
        )

        let errors = CustomRuleValidator.validate(rule, existingRules: existingRules)
        if let firstError = errors.first {
            switch firstError {
            case let .invalidInputKey(key):
                validationError = "Invalid input key: \(key)"
            case let .invalidOutputKey(key):
                validationError = "Invalid output key: \(key)"
            case .selfMapping:
                validationError = "Input and output are the same"
            case let .conflict(name, _):
                validationError = "Conflicts with '\(name)'"
            case .emptyInput, .emptyOutput:
                validationError = "Keys cannot be empty"
            }
            return
        }

        onSave(rule)
        dismiss()
    }
}

// MARK: - Key Display Name Helper

private enum KeyDisplayName {
    static func display(for kanataKey: String) -> String {
        let displayNames: [String: String] = [
            // Special combo modifiers
            "hyper": "✦ Hyper",
            "meh": "◇ Meh",
            // Standard modifiers
            "lmet": "⌘ Cmd",
            "rmet": "⌘ Cmd",
            "lctl": "⌃ Ctrl",
            "rctl": "⌃ Ctrl",
            "lalt": "⌥ Opt",
            "ralt": "⌥ Opt",
            "lsft": "⇧ Shift",
            "rsft": "⇧ Shift",
            "caps": "⇪ Caps Lock",
            "tab": "⇥ Tab",
            "ret": "↩ Return",
            "spc": "Space",
            "bspc": "⌫ Delete",
            "del": "⌦ Fwd Del",
            "esc": "⎋ Escape",
            "up": "↑ Up",
            "down": "↓ Down",
            "left": "← Left",
            "right": "→ Right",
            "pgup": "Page Up",
            "pgdn": "Page Down",
            "home": "Home",
            "end": "End",
            "fn": "fn",
            "f1": "F1", "f2": "F2", "f3": "F3", "f4": "F4",
            "f5": "F5", "f6": "F6", "f7": "F7", "f8": "F8",
            "f9": "F9", "f10": "F10", "f11": "F11", "f12": "F12",
            "f13": "F13", "f14": "F14", "f15": "F15",
            "brdn": "🔅 Brightness Down", "brup": "🔆 Brightness Up",
            "mute": "🔇 Mute", "vold": "🔉 Volume Down", "volu": "🔊 Volume Up",
            "prev": "⏮ Previous", "pp": "⏯ Play/Pause", "next": "⏭ Next"
        ]

        var result = kanataKey
        var modPrefix = ""

        if result.hasPrefix("M-") {
            modPrefix += "⌘"
            result = String(result.dropFirst(2))
        }
        if result.hasPrefix("C-") {
            modPrefix += "⌃"
            result = String(result.dropFirst(2))
        }
        if result.hasPrefix("A-") {
            modPrefix += "⌥"
            result = String(result.dropFirst(2))
        }
        if result.hasPrefix("S-") {
            modPrefix += "⇧"
            result = String(result.dropFirst(2))
        }

        let baseName = displayNames[result] ?? result.uppercased()

        if modPrefix.isEmpty {
            return baseName
        } else {
            return "\(modPrefix) \(baseName)"
        }
    }
}

// MARK: - Preview

#Preview("Create") {
    CustomRuleEditorView(
        rule: nil,
        existingRules: [],
        onSave: { _ in },
        onDelete: nil
    )
}

#Preview("Edit") {
    CustomRuleEditorView(
        rule: CustomRule(
            id: UUID(),
            title: "Caps to Escape",
            input: "caps",
            output: "esc",
            isEnabled: true,
            notes: nil,
            createdAt: Date(),
            behavior: nil
        ),
        existingRules: [],
        onSave: { _ in },
        onDelete: { _ in }
    )
}

#Preview("With Behavior") {
    CustomRuleEditorView(
        rule: CustomRule(
            id: UUID(),
            title: "",
            input: "caps",
            output: "esc",
            isEnabled: true,
            notes: nil,
            createdAt: Date(),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: "esc",
                holdAction: "lctl",
                tapTimeout: 200,
                holdTimeout: 200,
                activateHoldOnOtherKey: false,
                quickTap: false
            ))
        ),
        existingRules: [],
        onSave: { _ in },
        onDelete: { _ in }
    )
}
