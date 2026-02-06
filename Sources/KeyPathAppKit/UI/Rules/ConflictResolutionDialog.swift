import SwiftUI

// MARK: - Conflict Types

/// Represents a pending conflict between Hold and Tap Dance behaviors
struct BehaviorConflict {
    let attemptedField: AttemptedField
    let existingHoldAction: String
    let existingTapDanceActions: [String]

    enum AttemptedField {
        case hold
        case tapDance(index: Int)
    }
}

/// User's choice when resolving a Hold vs Tap Dance conflict
enum BehaviorConflictChoice {
    case keepHold
    case keepTapDance
}

// MARK: - Conflict Resolution Dialog

/// A dialog that appears when user tries to set Hold when Tap Dance exists (or vice versa)
struct ConflictResolutionDialog: View {
    let pendingConflict: BehaviorConflict?
    let onChoice: (BehaviorConflictChoice) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with illustration
            VStack(spacing: 16) {
                // Illustration showing the fork in the road
                HStack(spacing: 0) {
                    // Hold path
                    VStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                        Text("Hold")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80)

                    // Fork illustration
                    forkIllustration

                    // Tap Dance path
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.purple)
                        Text("Tap Dance")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80)
                }
                .padding(.top, 20)

                Text("Choose One")
                    .font(.title2.weight(.semibold))

                Text("Kanata can't detect both hold duration and tap count on the same key. Which behavior do you want to keep?")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)

            Divider()

            // Current values section
            currentValuesSection

            Divider()

            // Action buttons
            actionButtons
        }
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Fork Illustration

    private var forkIllustration: some View {
        ZStack {
            // Left branch
            Path { path in
                path.move(to: CGPoint(x: 40, y: 60))
                path.addCurve(
                    to: CGPoint(x: 0, y: 0),
                    control1: CGPoint(x: 40, y: 30),
                    control2: CGPoint(x: 20, y: 10)
                )
            }
            .stroke(Color.orange.opacity(0.6), lineWidth: 3)

            // Right branch
            Path { path in
                path.move(to: CGPoint(x: 40, y: 60))
                path.addCurve(
                    to: CGPoint(x: 80, y: 0),
                    control1: CGPoint(x: 40, y: 30),
                    control2: CGPoint(x: 60, y: 10)
                )
            }
            .stroke(Color.purple.opacity(0.6), lineWidth: 3)

            // Center stem
            Path { path in
                path.move(to: CGPoint(x: 40, y: 80))
                path.addLine(to: CGPoint(x: 40, y: 60))
            }
            .stroke(Color.secondary.opacity(0.4), lineWidth: 3)

            // Decision point
            Circle()
                .fill(Color(NSColor.windowBackgroundColor))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                )
                .offset(y: 20)
        }
        .frame(width: 80, height: 80)
    }

    // MARK: - Current Values Section

    private var currentValuesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Hold value
            if let conflict = pendingConflict, !conflict.existingHoldAction.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.orange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Hold Action")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(KeyDisplayName.display(for: conflict.existingHoldAction))
                            .font(.body.weight(.medium))
                    }

                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }

            // Tap Dance values
            if let conflict = pendingConflict, !conflict.existingTapDanceActions.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(.purple)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Tap Dance Actions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            ForEach(Array(conflict.existingTapDanceActions.enumerated()), id: \.offset) { index, action in
                                HStack(spacing: 4) {
                                    Text("\(index + 2)×")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(KeyDisplayName.display(for: action))
                                        .font(.body.weight(.medium))
                                }
                                if index < conflict.existingTapDanceActions.count - 1 {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.1))
                )
            }
        }
        .padding(20)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("conflict-resolution-cancel-button")
            .accessibilityLabel("Cancel")

            Spacer()

            if let conflict = pendingConflict {
                // Always show both options so user can choose either direction

                // Tap Dance option - prominent if it's what they're trying to add
                if conflict.existingTapDanceActions.isEmpty {
                    // User is trying to add tap dance, make it prominent
                    Button {
                        onChoice(.keepTapDance)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap.fill")
                            Text("Switch to Tap")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .accessibilityIdentifier("conflict-resolution-switch-to-tap-button")
                    .accessibilityLabel("Switch to Tap")
                } else {
                    // User has tap dance, offer to keep it
                    Button {
                        onChoice(.keepTapDance)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap.fill")
                            Text("Keep Tap Dance")
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("conflict-resolution-keep-tap-dance-button")
                    .accessibilityLabel("Keep Tap Dance")
                }

                // Hold option - prominent if it's what they're trying to add
                if conflict.existingHoldAction.isEmpty {
                    // User is trying to add hold, make it prominent
                    Button {
                        onChoice(.keepHold)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.raised.fill")
                            Text("Switch to Hold")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityIdentifier("conflict-resolution-switch-to-hold-button")
                    .accessibilityLabel("Switch to Hold")
                } else {
                    // User has hold, offer to keep it
                    Button {
                        onChoice(.keepHold)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.raised.fill")
                            Text("Keep Hold")
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("conflict-resolution-keep-hold-button")
                    .accessibilityLabel("Keep Hold")
                }
            }
        }
        .padding(20)
    }
}

// MARK: - Key Display Name Helper

/// Converts Kanata key codes to human-readable display names
enum KeyDisplayName {
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
