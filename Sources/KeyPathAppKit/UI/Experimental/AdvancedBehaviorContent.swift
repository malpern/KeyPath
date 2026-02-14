import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Mini Action Keycap (for advanced section)

/// Smaller keycap for hold/double-tap actions in the advanced section.
struct MiniActionKeycap: View {
    let label: String
    let isRecording: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    private let size: CGFloat = 60
    private let cornerRadius: CGFloat = 8
    private let fontSize: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                )

            if isRecording {
                Text("...")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
            } else if label.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: fontSize * 0.7, weight: .light))
                    .foregroundStyle(foregroundColor.opacity(0.4))
            } else {
                Text(label.uppercased())
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
            onTap()
        }
    }

    private var foregroundColor: Color {
        Color(red: 0.88, green: 0.93, blue: 1.0)
            .opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
        if isRecording {
            Color.accentColor
        } else if isHovered {
            Color(white: 0.15)
        } else {
            Color(white: 0.08)
        }
    }

    private var borderColor: Color {
        if isRecording {
            Color.accentColor.opacity(0.8)
        } else if isHovered {
            Color.white.opacity(0.3)
        } else {
            Color.white.opacity(0.15)
        }
    }

    private var shadowColor: Color {
        Color.black.opacity(0.5)
    }

    private var shadowRadius: CGFloat {
        isPressed ? 1 : 2
    }

    private var shadowOffset: CGFloat {
        isPressed ? 1 : 2
    }
}

// MARK: - Advanced Behavior Content

/// Content showing hold and double-tap options with mini keycaps (toggle is in sidebar).
struct AdvancedBehaviorContent: View {
    @ObservedObject var viewModel: MapperViewModel

    var body: some View {
        VStack(spacing: 16) {
            // On Hold row
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Text("On Hold")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)

                    MiniActionKeycap(
                        label: viewModel.holdAction.isEmpty ? "" : formatKeyForDisplay(viewModel.holdAction),
                        isRecording: viewModel.isRecordingHold,
                        onTap: { viewModel.toggleHoldRecording() }
                    )

                    if !viewModel.holdAction.isEmpty {
                        Button {
                            viewModel.holdAction = ""
                            viewModel.holdBehavior = .basic
                            viewModel.customTapKeysText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Clear hold action")
                        .accessibilityIdentifier("mapper-clear-hold-button")
                        .accessibilityLabel("Clear hold action")
                    }

                    Spacer()
                }

                // Hold behavior options (shown when hold action is set)
                if !viewModel.holdAction.isEmpty {
                    holdBehaviorPicker
                        .padding(.leading, 86) // Align with keycap
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Double Tap row
            HStack(spacing: 16) {
                Text("Double Tap")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)

                MiniActionKeycap(
                    label: viewModel.doubleTapAction.isEmpty ? "" : formatKeyForDisplay(viewModel.doubleTapAction),
                    isRecording: viewModel.isRecordingDoubleTap,
                    onTap: { viewModel.toggleDoubleTapRecording() }
                )

                if !viewModel.doubleTapAction.isEmpty {
                    Button {
                        viewModel.doubleTapAction = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Clear double tap action")
                    .accessibilityIdentifier("mapper-clear-double-tap-button")
                    .accessibilityLabel("Clear double tap action")
                }

                Spacer()
            }

            // Triple+ Tap rows (dynamically added)
            ForEach(viewModel.tapDanceSteps.indices, id: \.self) { index in
                let step = viewModel.tapDanceSteps[index]
                HStack(spacing: 16) {
                    Text(step.label)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .trailing)

                    MiniActionKeycap(
                        label: step.action.isEmpty ? "" : formatKeyForDisplay(step.action),
                        isRecording: step.isRecording,
                        onTap: { viewModel.toggleTapDanceRecording(at: index) }
                    )

                    if !step.action.isEmpty {
                        Button {
                            viewModel.clearTapDanceStep(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Clear \(step.label.lowercased()) action")
                    }

                    // Remove button for this step
                    Button {
                        viewModel.removeTapDanceStep(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(step.label.lowercased())")

                    Spacer()
                }
            }

            // "+ Triple Tap" link (only if we can add more)
            if viewModel.tapDanceSteps.count < MapperViewModel.tapDanceLabels.count {
                HStack(spacing: 16) {
                    Text("")
                        .frame(width: 70)

                    Button {
                        viewModel.addTapDanceStep()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                            Text(nextTapDanceLabel)
                                .font(.subheadline)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add \(nextTapDanceLabel.lowercased())")
                    .accessibilityIdentifier("mapper-add-tap-dance-button")
                    .accessibilityLabel("Add \(nextTapDanceLabel.lowercased())")

                    Spacer()
                }
            }

            // Timing row
            HStack(spacing: 16) {
                Text("Timing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .trailing)

                if viewModel.showTimingAdvanced {
                    // Separate timing fields
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tap")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                TextField("", value: $viewModel.tapTimeout, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hold")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                TextField("", value: $viewModel.holdTimeout, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                            }
                            Text("ms")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // Single timing value
                    HStack(spacing: 8) {
                        TextField("", value: $viewModel.tappingTerm, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)

                        Text("ms")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Gear icon to toggle advanced timing
                Button {
                    viewModel.showTimingAdvanced.toggle()
                    if viewModel.showTimingAdvanced {
                        // Initialize separate values from single
                        viewModel.tapTimeout = viewModel.tappingTerm
                        viewModel.holdTimeout = viewModel.tappingTerm
                    } else {
                        // Sync single value from tap timeout
                        viewModel.tappingTerm = viewModel.tapTimeout
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.subheadline)
                        .foregroundColor(viewModel.showTimingAdvanced ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(viewModel.showTimingAdvanced ? "Use single timing" : "Separate tap/hold timing")
                .accessibilityIdentifier("mapper-timing-advanced-button")
                .accessibilityLabel("Toggle advanced timing")

                Spacer()
            }
        }
        .padding(.leading, 8)
        .animation(.easeInOut(duration: 0.2), value: viewModel.holdAction.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: viewModel.tapDanceSteps.count)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showTimingAdvanced)
    }

    // MARK: - Hold Behavior Picker

    private var holdBehaviorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MapperViewModel.HoldBehaviorType.allCases, id: \.self) { behaviorType in
                HStack(spacing: 10) {
                    Button {
                        viewModel.holdBehavior = behaviorType
                    } label: {
                        Image(systemName: viewModel.holdBehavior == behaviorType ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundColor(viewModel.holdBehavior == behaviorType ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(behaviorType.rawValue)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        if viewModel.holdBehavior == behaviorType {
                            Text(behaviorType.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityIdentifier("mapper-hold-behavior-\(behaviorType.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
                .accessibilityLabel(behaviorType.rawValue)

                // Custom keys input (shown when Custom keys is selected)
                if behaviorType == .customKeys, viewModel.holdBehavior == .customKeys {
                    TextField("e.g., a s d f", text: $viewModel.customTapKeysText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .font(.subheadline)
                        .padding(.leading, 26)
                        .accessibilityIdentifier("mapper-custom-tap-keys-field")
                        .accessibilityLabel("Custom tap keys")
                }
            }
        }
    }

    // MARK: - Helpers

    private var nextTapDanceLabel: String {
        let index = viewModel.tapDanceSteps.count
        guard index < MapperViewModel.tapDanceLabels.count else { return "More Taps" }
        return MapperViewModel.tapDanceLabels[index]
    }

    private func formatKeyForDisplay(_ key: String) -> String {
        let displayMap: [String: String] = [
            "lctl": "⌃", "rctl": "⌃", "leftctrl": "⌃", "rightctrl": "⌃",
            "lalt": "⌥", "ralt": "⌥", "leftalt": "⌥", "rightalt": "⌥",
            "lsft": "⇧", "rsft": "⇧", "leftshift": "⇧", "rightshift": "⇧",
            "lmet": "⌘", "rmet": "⌘", "leftmeta": "⌘", "rightmeta": "⌘",
            "caps": "⇪", "capslock": "⇪",
            "spc": "⎵", "space": "⎵",
            "ret": "↩", "enter": "↩",
            "tab": "⇥",
            "bspc": "⌫", "backspace": "⌫",
            "esc": "⎋", "escape": "⎋",
            "left": "←", "right": "→", "up": "↑", "down": "↓"
        ]
        return displayMap[key.lowercased()] ?? key.uppercased()
    }
}
