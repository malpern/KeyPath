import AppKit
import KeyPathCore
import SwiftUI

extension OverlayInspectorPanel {
    /// Content for the Tap & Hold slide-over panel (Apple-style 80/20 design)
    var tapHoldPanelContent: some View {
        TapHoldCardView(
            keyLabel: tapHoldKeyLabel,
            keyCode: tapHoldKeyCode,
            initialSlot: tapHoldInitialSlot,
            tapAction: $tapHoldTapAction,
            holdAction: $tapHoldHoldAction,
            comboAction: $tapHoldComboAction,
            responsiveness: $tapHoldResponsiveness,
            useTapImmediately: $tapHoldUseTapImmediately
        )
        .padding(.horizontal, 4)
    }

    /// Content for the slide-over customize panel - tap-hold focused (legacy)
    var customizePanelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // On Hold row
            customizeRow(
                label: "On Hold",
                action: customizeHoldAction,
                fieldId: "hold",
                onClear: { customizeHoldAction = "" }
            )

            // Double Tap row
            customizeRow(
                label: "Double Tap",
                action: customizeDoubleTapAction,
                fieldId: "doubleTap",
                onClear: { customizeDoubleTapAction = "" }
            )

            // Triple+ Tap rows (dynamically added)
            ForEach(Array(customizeTapDanceSteps.enumerated()), id: \.offset) { index, step in
                customizeTapDanceRow(index: index, step: step)
            }

            // "+ Triple Tap" link (only if we can add more)
            if customizeTapDanceSteps.count < Self.tapDanceLabels.count {
                HStack(spacing: 16) {
                    Text("")
                        .frame(width: 70)

                    Button {
                        let label = Self.tapDanceLabels[customizeTapDanceSteps.count]
                        customizeTapDanceSteps.append((label: label, action: ""))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                            Text(Self.tapDanceLabels[customizeTapDanceSteps.count])
                                .font(.subheadline)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("customize-add-tap-dance")
                    .accessibilityLabel("Add \(Self.tapDanceLabels[customizeTapDanceSteps.count])")

                    Spacer()
                }
            }

            // Timing row
            customizeTimingRow

            Spacer()
        }
        .padding(.horizontal, 12)
        .onDisappear {
            stopCustomizeRecording()
        }
    }

    /// Start recording for a specific field
    private func startCustomizeRecording(fieldId: String) {
        // Stop any existing recording first
        stopCustomizeRecording()

        customizeRecordingField = fieldId

        // Add local key event monitor
        customizeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Get the key name from the event
            let keyName = keyNameFromEvent(event)

            // Update the appropriate field
            DispatchQueue.main.async {
                setCustomizeFieldValue(fieldId: fieldId, value: keyName)
                stopCustomizeRecording()
            }

            // Consume the event so it doesn't propagate
            return nil
        }
    }

    /// Stop any active recording
    private func stopCustomizeRecording() {
        if let monitor = customizeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            customizeKeyMonitor = nil
        }
        customizeRecordingField = nil
    }

    /// Toggle recording for a field
    private func toggleCustomizeRecording(fieldId: String) {
        if customizeRecordingField == fieldId {
            stopCustomizeRecording()
        } else {
            startCustomizeRecording(fieldId: fieldId)
        }
    }

    /// Set the value for a customize field by ID
    private func setCustomizeFieldValue(fieldId: String, value: String) {
        switch fieldId {
        case "hold":
            customizeHoldAction = value
        case "doubleTap":
            customizeDoubleTapAction = value
        default:
            // Handle tap-dance steps (e.g., "tapDance-0")
            if fieldId.hasPrefix("tapDance-"),
               let indexStr = fieldId.split(separator: "-").last,
               let index = Int(indexStr),
               index < customizeTapDanceSteps.count
            {
                customizeTapDanceSteps[index].action = value
            }
        }
    }

    /// Convert NSEvent to a key name string
    private func keyNameFromEvent(_ event: NSEvent) -> String {
        // Check for modifier-only keys first
        let flags = event.modifierFlags

        // Map common keyCodes to kanata key names
        let keyCodeMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "ret",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "spc",
            50: "`", 51: "bspc", 53: "esc",
            // Modifiers
            54: "rsft", 55: "lmet", 56: "lsft", 57: "caps", 58: "lalt",
            59: "lctl", 60: "rsft", 61: "ralt", 62: "rctl",
            // Function keys
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
            98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
            // Arrow keys
            123: "left", 124: "right", 125: "down", 126: "up",
            // Other
            117: "del", 119: "end", 121: "pgdn", 115: "home", 116: "pgup",
        ]

        if let keyName = keyCodeMap[event.keyCode] {
            // Build modifier prefix if any non-modifier key
            var result = ""
            if flags.contains(.control) { result += "C-" }
            if flags.contains(.option) { result += "A-" }
            if flags.contains(.shift), !["lsft", "rsft"].contains(keyName) { result += "S-" }
            if flags.contains(.command) { result += "M-" }
            return result + keyName
        }

        // Fallback to characters
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.lowercased()
        }

        return "unknown"
    }

    /// A row for hold/double-tap action with mini keycap
    private func customizeRow(label: String, action: String, fieldId: String, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            TapHoldMiniKeycap(
                label: action.isEmpty ? "" : formatKeyForCustomize(action),
                isRecording: customizeRecordingField == fieldId,
                onTap: {
                    toggleCustomizeRecording(fieldId: fieldId)
                }
            )
            .accessibilityIdentifier("customize-\(fieldId)-keycap")
            .accessibilityLabel("\(label) action keycap")

            if !action.isEmpty {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("customize-\(fieldId)-clear")
                .accessibilityLabel("Clear \(label.lowercased()) action")
            }

            Spacer()
        }
    }

    /// A row for tap-dance steps (triple tap, quad tap, etc.)
    private func customizeTapDanceRow(index: Int, step: (label: String, action: String)) -> some View {
        HStack(spacing: 12) {
            Text(step.label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            TapHoldMiniKeycap(
                label: step.action.isEmpty ? "" : formatKeyForCustomize(step.action),
                isRecording: customizeRecordingField == "tapDance-\(index)",
                onTap: {
                    toggleCustomizeRecording(fieldId: "tapDance-\(index)")
                }
            )
            .accessibilityIdentifier("customize-tapDance-\(index)-keycap")
            .accessibilityLabel("\(step.label) action keycap")

            if !step.action.isEmpty {
                Button {
                    customizeTapDanceSteps[index].action = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("customize-tapDance-\(index)-clear")
                .accessibilityLabel("Clear \(step.label.lowercased()) action")
            }

            // Remove button
            Button {
                customizeTapDanceSteps.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("customize-tapDance-\(index)-remove")
            .accessibilityLabel("Remove \(step.label.lowercased())")

            Spacer()
        }
    }

    /// Timing configuration row
    private var customizeTimingRow: some View {
        HStack(spacing: 12) {
            Text("Timing")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            if customizeShowTimingAdvanced {
                // Separate tap/hold fields
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tap")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("", value: $customizeTapTimeout, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .accessibilityIdentifier("customize-tap-timeout")
                                .accessibilityLabel("Tap timeout in milliseconds")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hold")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("", value: $customizeHoldTimeout, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .accessibilityIdentifier("customize-hold-timeout")
                                .accessibilityLabel("Hold timeout in milliseconds")
                        }
                        Text("ms")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Single timing value
                HStack(spacing: 8) {
                    TextField("", value: $customizeTapTimeout, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .accessibilityIdentifier("customize-timing")
                        .accessibilityLabel("Timing in milliseconds")

                    Text("ms")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Gear icon to toggle advanced timing
            Button {
                customizeShowTimingAdvanced.toggle()
                if customizeShowTimingAdvanced {
                    customizeHoldTimeout = customizeTapTimeout
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline)
                    .foregroundColor(customizeShowTimingAdvanced ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("customize-timing-advanced-toggle")
            .accessibilityLabel(customizeShowTimingAdvanced ? "Use single timing value" : "Use separate tap and hold timing")

            Spacer()
        }
    }

    /// Format a key name for display in customize panel
    private func formatKeyForCustomize(_ key: String) -> String {
        // Handle common modifier names
        switch key.lowercased() {
        case "lmet", "rmet", "met": "⌘"
        case "lalt", "ralt", "alt": "⌥"
        case "lctl", "rctl", "ctl": "⌃"
        case "lsft", "rsft", "sft": "⇧"
        case "space", "spc": "␣"
        case "ret", "return", "enter": "↩"
        case "bspc", "backspace": "⌫"
        case "tab": "⇥"
        case "esc", "escape": "⎋"
        default: key.uppercased()
        }
    }
}
