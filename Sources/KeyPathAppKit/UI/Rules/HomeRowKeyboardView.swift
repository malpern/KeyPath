import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Visual keyboard representation for home row mods
struct HomeRowKeyboardView: View {
    let enabledKeys: Set<String>
    let modifierAssignments: [String: String]
    let selectedKey: String?
    let onKeySelected: (String) -> Void

    @State private var hoveredKey: String?

    private let leftHandKeys = ["a", "s", "d", "f"]
    private let rightHandKeys = ["j", "k", "l", ";"]

    var body: some View {
        VStack(spacing: 16) {
            // Visual keyboard layout
            HStack(spacing: 12) {
                // Left hand
                HStack(spacing: 8) {
                    ForEach(leftHandKeys, id: \.self) { key in
                        HomeRowKeyChip(
                            key: key,
                            modifier: modifierAssignments[key],
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
                    }
                }

                // Spacer between hands
                Spacer()
                    .frame(width: 32)

                // Right hand
                HStack(spacing: 8) {
                    ForEach(rightHandKeys, id: \.self) { key in
                        HomeRowKeyChip(
                            key: key,
                            modifier: modifierAssignments[key],
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
                    }
                }
            }
            .padding(.vertical, 8)

            // Helper text
            Text("Tap for letter, hold for modifier")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
}

/// Interactive key chip for home row mods
struct HomeRowKeyChip: View {
    let key: String
    let modifier: String?
    let isEnabled: Bool
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    @State private var isPressed = false

    private var keyDisplay: String {
        key.uppercased()
    }

    private var modifierDisplay: String {
        guard let modifier else { return "" }
        let displayNames: [String: String] = [
            "lmet": "⌘", "rmet": "⌘",
            "lalt": "⌥", "ralt": "⌥",
            "lctl": "⌃", "rctl": "⌃",
            "lsft": "⇧", "rsft": "⇧"
        ]
        return displayNames[modifier] ?? modifier
    }

    var body: some View {
        VStack(spacing: 4) {
            // Key label
            Text(keyDisplay)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(textColor)

            // Modifier symbol
            if modifier != nil, isEnabled {
                Text(modifierDisplay)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(textColor.opacity(0.8))
            } else if !isEnabled {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
        }
        .frame(width: 64, height: 64)
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
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            Task { @MainActor in
                try await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
                onTap()
            }
        }
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
