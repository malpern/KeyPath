import KeyPathCore
import SwiftUI

struct CustomRuleEditorView: View {
    enum Mode {
        case create
        case edit
    }

    @Environment(\.dismiss) private var dismiss
    @State private var customName: String
    @State private var isEditingName: Bool = false
    @State private var input: String
    @State private var output: String
    @State private var isEnabled: Bool
    @State private var behavior: MappingBehavior?
    @State private var showAdvanced: Bool = false
    @State private var isRecordingInput: Bool = false
    @State private var isRecordingOutput: Bool = false
    @State private var validationError: String?
    @State private var showDeleteConfirmation = false

    // Tap dance states
    @State private var tapAction: String = ""
    @State private var holdAction: String = ""
    @State private var doubleTapAction: String = ""
    @State private var tapHoldAction: String = ""
    @State private var tappingTerm: Int = 200
    @State private var isRecordingTap: Bool = false
    @State private var isRecordingHold: Bool = false
    @State private var isRecordingDoubleTap: Bool = false
    @State private var isRecordingTapHold: Bool = false

    private let existingRule: CustomRule?
    private let existingRules: [CustomRule]
    private let mode: Mode
    let onSave: (CustomRule) -> Void
    let onDelete: ((CustomRule) -> Void)?

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
            return "New Mapping"
        }
    }

    private var canSave: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
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

                    // Advanced options (tap dance)
                    advancedSection

                    // Validation error
                    if let error = validationError {
                        Text(error)
                            .font(.caption)
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
        .frame(width: 420, height: showAdvanced ? 580 : 320)
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

    // MARK: - Header

    private var header: some View {
        HStack {
            // Editable name
            if isEditingName {
                TextField("Name (optional)", text: $customName)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .onSubmit { isEditingName = false }
            } else {
                Button {
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

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
    }

    // MARK: - Key Input Field (Main Page Style)

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
                // Large input field
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))

                    if isRecording.wrappedValue {
                        Text("Press a key...")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                    } else if key.wrappedValue.isEmpty {
                        Text("Click record or type key name")
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 16)
                    } else {
                        HStack {
                            Text(KeyDisplayName.display(for: key.wrappedValue))
                                .font(.system(.body, design: .default).weight(.bold))
                                .foregroundColor(.primary)
                            Spacer()
                            // Small text showing kanata code
                            Text(key.wrappedValue)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .frame(height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isRecording.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.2),
                            lineWidth: isRecording.wrappedValue ? 2 : 1
                        )
                )
                .onTapGesture {
                    // Allow clicking the field to start recording
                    if !isRecording.wrappedValue && !anyOtherRecording(except: isRecording) {
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
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
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
            $isRecordingTap, $isRecordingHold,
            $isRecordingDoubleTap, $isRecordingTapHold
        ]
        return allRecordings.contains { $0.wrappedValue && $0.wrappedValue != current.wrappedValue }
    }

    // MARK: - Advanced Section (Tap Dance)

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(spacing: 16) {
                // Tap action
                actionSlot(
                    label: "On tap",
                    key: $tapAction,
                    isRecording: $isRecordingTap
                )

                // Hold action
                actionSlot(
                    label: "On hold",
                    key: $holdAction,
                    isRecording: $isRecordingHold
                )

                // Double tap action
                actionSlot(
                    label: "On double tap",
                    key: $doubleTapAction,
                    isRecording: $isRecordingDoubleTap
                )

                // Tap + hold action
                actionSlot(
                    label: "On tap + hold",
                    key: $tapHoldAction,
                    isRecording: $isRecordingTapHold
                )

                // Tapping term
                HStack {
                    Text("Tapping term (ms)")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                    Stepper(
                        value: $tappingTerm,
                        in: 100 ... 400,
                        step: 25
                    ) {
                        Text("\(tappingTerm)")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .onChange(of: tappingTerm) { _, _ in syncBehavior() }
                }
                .padding(.top, 8)
            }
            .padding(.top, 12)
        } label: {
            HStack {
                Text("Tap / Hold Actions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if behavior != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .onChange(of: showAdvanced) { _, isExpanded in
            if !isExpanded {
                // Clear behavior when collapsing
                behavior = nil
                tapAction = ""
                holdAction = ""
                doubleTapAction = ""
                tapHoldAction = ""
            } else {
                // Initialize tap action from output
                if tapAction.isEmpty {
                    tapAction = output
                }
            }
        }
    }

    @ViewBuilder
    private func actionSlot(
        label: String,
        key: Binding<String>,
        isRecording: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)

            // Action display box
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))

                if isRecording.wrappedValue {
                    Text("Press key...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                } else if key.wrappedValue.isEmpty {
                    Text("")
                        .padding(.horizontal, 12)
                } else {
                    Text(KeyDisplayName.display(for: key.wrappedValue))
                        .font(.system(.callout, design: .default).weight(.bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                }
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isRecording.wrappedValue ? Color.accentColor : Color.secondary.opacity(0.2),
                        lineWidth: isRecording.wrappedValue ? 2 : 1
                    )
            )
            .onTapGesture {
                if !isRecording.wrappedValue && !anyOtherRecording(except: isRecording) {
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
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isRecording.wrappedValue ? Color.red : Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
        }
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
            return nil // Consume the event
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

        // Build modifier prefix
        var prefix = ""
        if modifiers.contains(.command) { prefix += "M-" }
        if modifiers.contains(.control) { prefix += "C-" }
        if modifiers.contains(.option) { prefix += "A-" }
        if modifiers.contains(.shift) { prefix += "S-" }

        // Map key code to kanata name
        let keyName: String
        switch keyCode {
        case 0: keyName = "a"
        case 1: keyName = "s"
        case 2: keyName = "d"
        case 3: keyName = "f"
        case 4: keyName = "h"
        case 5: keyName = "g"
        case 6: keyName = "z"
        case 7: keyName = "x"
        case 8: keyName = "c"
        case 9: keyName = "v"
        case 11: keyName = "b"
        case 12: keyName = "q"
        case 13: keyName = "w"
        case 14: keyName = "e"
        case 15: keyName = "r"
        case 16: keyName = "y"
        case 17: keyName = "t"
        case 18: keyName = "1"
        case 19: keyName = "2"
        case 20: keyName = "3"
        case 21: keyName = "4"
        case 22: keyName = "6"
        case 23: keyName = "5"
        case 24: keyName = "="
        case 25: keyName = "9"
        case 26: keyName = "7"
        case 27: keyName = "-"
        case 28: keyName = "8"
        case 29: keyName = "0"
        case 30: keyName = "]"
        case 31: keyName = "o"
        case 32: keyName = "u"
        case 33: keyName = "["
        case 34: keyName = "i"
        case 35: keyName = "p"
        case 36: keyName = "ret"
        case 37: keyName = "l"
        case 38: keyName = "j"
        case 39: keyName = "'"
        case 40: keyName = "k"
        case 41: keyName = ";"
        case 42: keyName = "\\"
        case 43: keyName = ","
        case 44: keyName = "/"
        case 45: keyName = "n"
        case 46: keyName = "m"
        case 47: keyName = "."
        case 48: keyName = "tab"
        case 49: keyName = "spc"
        case 50: keyName = "`"
        case 51: keyName = "bspc"
        case 53: keyName = "esc"
        case 55: keyName = "lmet"
        case 56: keyName = "lsft"
        case 57: keyName = "caps"
        case 58: keyName = "lalt"
        case 59: keyName = "lctl"
        case 60: keyName = "rsft"
        case 61: keyName = "ralt"
        case 62: keyName = "rctl"
        case 63: keyName = "fn"
        case 96: keyName = "f5"
        case 97: keyName = "f6"
        case 98: keyName = "f7"
        case 99: keyName = "f3"
        case 100: keyName = "f8"
        case 101: keyName = "f9"
        case 103: keyName = "f11"
        case 105: keyName = "f13"
        case 107: keyName = "f14"
        case 109: keyName = "f10"
        case 111: keyName = "f12"
        case 113: keyName = "f15"
        case 118: keyName = "f4"
        case 119: keyName = "end"
        case 120: keyName = "f2"
        case 121: keyName = "pgdn"
        case 122: keyName = "f1"
        case 123: keyName = "left"
        case 124: keyName = "right"
        case 125: keyName = "down"
        case 126: keyName = "up"
        default: keyName = "k\(keyCode)"
        }

        return prefix + keyName
    }

    // MARK: - Behavior Sync

    private func initializeFromBehavior() {
        guard let behavior else { return }

        switch behavior {
        case let .dualRole(dr):
            tapAction = dr.tapAction
            holdAction = dr.holdAction
            tappingTerm = dr.tapTimeout

        case let .tapDance(td):
            tappingTerm = td.windowMs
            for (index, step) in td.steps.enumerated() {
                switch index {
                case 0: tapAction = step.action
                case 1: doubleTapAction = step.action
                case 2: holdAction = step.action // Use third step as hold
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

        // Check if we have any advanced actions configured
        let hasTap = !tapAction.isEmpty
        let hasHold = !holdAction.isEmpty
        let hasDoubleTap = !doubleTapAction.isEmpty
        let hasTapHold = !tapHoldAction.isEmpty

        if !hasTap && !hasHold && !hasDoubleTap && !hasTapHold {
            behavior = nil
            return
        }

        // If only tap and hold, use dual-role
        if hasTap && hasHold && !hasDoubleTap && !hasTapHold {
            behavior = .dualRole(DualRoleBehavior(
                tapAction: tapAction,
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
            steps.append(TapDanceStep(label: "Single tap", action: tapAction))
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

        // Sync behavior before saving
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

        // Validate with existing rules
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
        // Map kanata key names to display names
        let displayNames: [String: String] = [
            "lmet": "⌘ LCmd",
            "rmet": "⌘ RCmd",
            "lctl": "⌃ LCtrl",
            "rctl": "⌃ RCtrl",
            "lalt": "⌥ LOpt",
            "ralt": "⌥ ROpt",
            "lsft": "⇧ LShift",
            "rsft": "⇧ RShift",
            "caps": "⇪ Caps",
            "tab": "⇥ Tab",
            "ret": "↩ Return",
            "spc": "Space",
            "bspc": "⌫ Delete",
            "del": "⌦ Fwd Del",
            "esc": "⎋ Esc",
            "up": "↑",
            "down": "↓",
            "left": "←",
            "right": "→",
            "pgup": "Page Up",
            "pgdn": "Page Down",
            "home": "Home",
            "end": "End",
            "fn": "fn",
            "f1": "F1", "f2": "F2", "f3": "F3", "f4": "F4",
            "f5": "F5", "f6": "F6", "f7": "F7", "f8": "F8",
            "f9": "F9", "f10": "F10", "f11": "F11", "f12": "F12",
            "f13": "F13", "f14": "F14", "f15": "F15",
            "brdn": "🔅", "brup": "🔆",
            "mute": "🔇", "vold": "🔉", "volu": "🔊",
            "prev": "⏮", "pp": "⏯", "next": "⏭"
        ]

        // Handle modifier prefixes
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
            return "\(modPrefix)\(baseName)"
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
