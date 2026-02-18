import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Visual keyboard representation for home row mods
struct HomeRowKeyboardView: View {
    let enabledKeys: Set<String>
    let modifierAssignments: [String: String]
    let holdMode: HomeRowHoldMode
    let selectedKey: String?
    let keyDisplayLabels: [String: String]
    let helperText: String
    let keyPopoverContent: ((String) -> AnyView)?
    let onPopoverDismiss: (() -> Void)?
    let onKeySelected: (String) -> Void
    let keyChipSize: CGFloat

    @State private var hoveredKey: String?

    private let leftHandKeys = ["a", "s", "d", "f"]
    private let rightHandKeys = ["j", "k", "l", ";"]
    private var keySpacing: CGFloat {
        max(4, keyChipSize * 0.1)
    }

    private var handSpacing: CGFloat {
        max(14, keyChipSize * 0.3)
    }

    private var sectionSpacing: CGFloat {
        max(10, keyChipSize * 0.2)
    }

    private var verticalPadding: CGFloat {
        max(4, keyChipSize * 0.08)
    }

    private var outerPadding: CGFloat {
        max(8, keyChipSize * 0.15)
    }

    private var helperFontSize: CGFloat {
        max(11, keyChipSize * 0.18)
    }

    private var handLabelFont: Font {
        .caption
    }

    init(
        enabledKeys: Set<String>,
        modifierAssignments: [String: String],
        holdMode: HomeRowHoldMode = .modifiers,
        selectedKey: String?,
        keyDisplayLabels: [String: String] = [:],
        helperText: String = "Tap for letter, hold for modifier",
        keyChipSize: CGFloat = 78,
        keyPopoverContent: ((String) -> AnyView)? = nil,
        onPopoverDismiss: (() -> Void)? = nil,
        onKeySelected: @escaping (String) -> Void
    ) {
        self.enabledKeys = enabledKeys
        self.modifierAssignments = modifierAssignments
        self.holdMode = holdMode
        self.selectedKey = selectedKey
        self.keyDisplayLabels = keyDisplayLabels
        self.helperText = helperText
        self.keyChipSize = keyChipSize
        self.keyPopoverContent = keyPopoverContent
        self.onPopoverDismiss = onPopoverDismiss
        self.onKeySelected = onKeySelected
    }

    var body: some View {
        VStack(spacing: sectionSpacing) {
            // Visual keyboard layout
            HStack(spacing: keySpacing) {
                // Left hand
                VStack(alignment: .leading, spacing: keySpacing) {
                    handHeader(emoji: "\u{1FAF2}", title: "Left", isActive: hasEnabledKey(in: leftHandKeys))
                    HStack(spacing: keySpacing) {
                        ForEach(leftHandKeys, id: \.self) { key in
                            HomeRowKeyChip(
                                key: key,
                                keyDisplayLabel: keyDisplayLabel(for: key),
                                holdAssignment: modifierAssignments[key],
                                holdMode: holdMode,
                                size: keyChipSize,
                                isEnabled: enabledKeys.contains(key),
                                isSelected: selectedKey == key,
                                isHovered: hoveredKey == key,
                                onTap: { onKeySelected(key) },
                                onHover: { hovering in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        hoveredKey = hovering ? key : nil
                                    }
                                }
                            )
                            .popover(isPresented: popoverBinding(for: key), arrowEdge: .top) {
                                if let keyPopoverContent {
                                    keyPopoverContent(key)
                                } else {
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
                .opacity(hasEnabledKey(in: leftHandKeys) ? 1.0 : 0.45)

                // Spacer between hands
                Spacer()
                    .frame(width: handSpacing)

                // Right hand
                VStack(alignment: .leading, spacing: keySpacing) {
                    handHeader(emoji: "\u{1FAF1}", title: "Right", isActive: hasEnabledKey(in: rightHandKeys))
                    HStack(spacing: keySpacing) {
                        ForEach(rightHandKeys, id: \.self) { key in
                            HomeRowKeyChip(
                                key: key,
                                keyDisplayLabel: keyDisplayLabel(for: key),
                                holdAssignment: modifierAssignments[key],
                                holdMode: holdMode,
                                size: keyChipSize,
                                isEnabled: enabledKeys.contains(key),
                                isSelected: selectedKey == key,
                                isHovered: hoveredKey == key,
                                onTap: { onKeySelected(key) },
                                onHover: { hovering in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        hoveredKey = hovering ? key : nil
                                    }
                                }
                            )
                            .popover(isPresented: popoverBinding(for: key), arrowEdge: .top) {
                                if let keyPopoverContent {
                                    keyPopoverContent(key)
                                } else {
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
                .opacity(hasEnabledKey(in: rightHandKeys) ? 1.0 : 0.45)
            }
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity)
        }
        .padding(outerPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }

    private func keyDisplayLabel(for key: String) -> String {
        keyDisplayLabels[key] ?? key.uppercased()
    }

    private func handHeader(emoji: String, title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text("\(emoji) \(title)")
                .font(handLabelFont)
                .foregroundColor(.secondary)
            if !isActive {
                Text("Disabled")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))
            }
        }
    }

    private func hasEnabledKey(in handKeys: [String]) -> Bool {
        handKeys.contains(where: { enabledKeys.contains($0) })
    }

    private func popoverBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selectedKey == key && keyPopoverContent != nil },
            set: { isPresented in
                if !isPresented {
                    onPopoverDismiss?()
                }
            }
        )
    }
}

/// Interactive key chip for home row mods
struct HomeRowKeyChip: View {
    let key: String
    let keyDisplayLabel: String
    let holdAssignment: String?
    let holdMode: HomeRowHoldMode
    let size: CGFloat
    let isEnabled: Bool
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    @State private var isPressed = false
    private var letterFontSize: CGFloat {
        max(15, size * 0.27)
    }

    private var assignmentFontSize: CGFloat {
        max(12, size * 0.22)
    }

    private func modifierDisplay(for modifier: String) -> String {
        let displayNames: [String: String] = [
            "lmet": "⌘", "rmet": "⌘",
            "lalt": "⌥", "ralt": "⌥",
            "lctl": "⌃", "rctl": "⌃",
            "lsft": "⇧", "rsft": "⇧"
        ]
        return displayNames[modifier] ?? modifier
    }

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
                onTap()
            }
        }) {
            VStack(spacing: 4) {
                // Key label
                Text(keyDisplayLabel)
                    .font(.system(size: letterFontSize, weight: .semibold))
                    .foregroundColor(textColor)

                // Hold assignment
                if let holdAssignment, isEnabled {
                    if holdMode == .layers {
                        HomeRowLayerTargetChip(layerName: holdAssignment)
                    } else {
                        Text(modifierDisplay(for: holdAssignment))
                            .font(.system(size: assignmentFontSize, weight: .medium))
                            .foregroundColor(textColor.opacity(0.8))
                    }
                } else if !isEnabled {
                    Text("—")
                        .font(.system(size: max(11, size * 0.2)))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-row-key-chip-\(key)")
        .accessibilityLabel("Configure home row key \(keyDisplayLabel)")
        .onHover { hovering in
            onHover(hovering)
            #if os(macOS)
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            #endif
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            .accentColor
        } else if isHovered {
            Color(NSColor.controlAccentColor).opacity(0.2)
        } else if isEnabled {
            Color(NSColor.controlBackgroundColor)
        } else {
            Color(NSColor.controlBackgroundColor).opacity(0.3)
        }
    }

    private var textColor: Color {
        if isSelected {
            .white
        } else if isEnabled {
            .primary
        } else {
            .secondary.opacity(0.5)
        }
    }

    private var borderColor: Color {
        if isSelected {
            .accentColor
        } else if isHovered {
            Color(NSColor.controlAccentColor).opacity(0.5)
        } else {
            Color.secondary.opacity(0.2)
        }
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
    }
}

private struct HomeRowLayerTargetChip: View {
    let layerName: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: LayerInfo.iconName(for: layerName))
                .font(.system(size: 9, weight: .semibold))
            Text(LayerInfo.displayName(for: layerName))
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.14))
        )
        .overlay(
            Capsule()
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 0.6)
        )
    }
}
