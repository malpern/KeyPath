import KeyPathRulesCore
import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// Visual keyboard representation for home row mods
struct HomeRowKeyboardView<PopoverContent: View>: View {
    let enabledKeys: Set<String>
    let modifierAssignments: [String: String]
    let holdMode: HomeRowHoldMode
    let selectedKey: String?
    let keyDisplayLabels: [String: String]
    let helperText: String
    let keyPopoverContent: ((String) -> PopoverContent)?
    let onPopoverDismiss: (() -> Void)?
    let onKeySelected: (String) -> Void
    let keyChipSize: CGFloat
    var timingPreviewPhase: HomeRowModsCollectionView.TimingPreviewPhase = .idle

    @State private var hoveredKey: String?

    let leftHandKeys: [String]
    let rightHandKeys: [String]
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
        timingPreviewPhase: HomeRowModsCollectionView.TimingPreviewPhase = .idle,
        leftHandKeys: [String] = HomeRowModsConfig.leftHandKeys,
        rightHandKeys: [String] = HomeRowModsConfig.rightHandKeys,
        keyPopoverContent: ((String) -> PopoverContent)? = nil,
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
        self.timingPreviewPhase = timingPreviewPhase
        self.leftHandKeys = leftHandKeys
        self.rightHandKeys = rightHandKeys
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
                        ForEach(Array(leftHandKeys.enumerated()), id: \.element) { idx, key in
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
                                },
                                timingPreviewPhase: timingPreviewPhase,
                                timingPreviewIndex: idx
                            )
                            .popover(isPresented: popoverBinding(for: key), arrowEdge: .top) {
                                if let keyPopoverContent {
                                    keyPopoverContent(key)
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
                        ForEach(Array(rightHandKeys.enumerated()), id: \.element) { idx, key in
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
                                },
                                timingPreviewPhase: timingPreviewPhase,
                                timingPreviewIndex: leftHandKeys.count + idx
                            )
                            .popover(isPresented: popoverBinding(for: key), arrowEdge: .top) {
                                if let keyPopoverContent {
                                    keyPopoverContent(key)
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

extension HomeRowKeyboardView where PopoverContent == EmptyView {
    init(
        enabledKeys: Set<String>,
        modifierAssignments: [String: String],
        holdMode: HomeRowHoldMode = .modifiers,
        selectedKey: String?,
        keyDisplayLabels: [String: String] = [:],
        helperText: String = "Tap for letter, hold for modifier",
        keyChipSize: CGFloat = 78,
        timingPreviewPhase: HomeRowModsCollectionView.TimingPreviewPhase = .idle,
        leftHandKeys: [String] = HomeRowModsConfig.leftHandKeys,
        rightHandKeys: [String] = HomeRowModsConfig.rightHandKeys,
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
        self.timingPreviewPhase = timingPreviewPhase
        self.leftHandKeys = leftHandKeys
        self.rightHandKeys = rightHandKeys
        keyPopoverContent = nil
        self.onPopoverDismiss = onPopoverDismiss
        self.onKeySelected = onKeySelected
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
    var timingPreviewPhase: HomeRowModsCollectionView.TimingPreviewPhase = .idle
    var timingPreviewIndex: Int = 0

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
                if isEnabled, timingPreviewPhase == .modifier, let holdAssignment {
                    Text(modifierDisplay(for: holdAssignment))
                        .font(.system(size: letterFontSize, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text(keyDisplayLabel)
                        .font(.system(size: letterFontSize, weight: .semibold))
                        .foregroundColor(previewTextColor)

                    if let holdAssignment, isEnabled, timingPreviewPhase == .idle {
                        if holdMode == .layers {
                            HomeRowLayerTargetChip(layerName: holdAssignment)
                        } else {
                            Text(modifierDisplay(for: holdAssignment))
                                .font(.system(size: assignmentFontSize, weight: .medium))
                                .foregroundColor(previewTextColor.opacity(0.8))
                        }
                    } else if !isEnabled {
                        Text("—")
                            .font(.system(size: max(11, size * 0.2)))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(previewBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(previewBorderColor, lineWidth: borderWidth)
            )
            .scaleEffect(x: previewScaleX, y: previewScaleY, anchor: .bottom)
            .offset(y: previewOffsetY)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .animation(.spring(response: 0.18, dampingFraction: 0.75).delay(staggerDelay), value: timingPreviewPhase)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-row-key-chip-\(key)")
        .accessibilityLabel("Configure home row key \(keyDisplayLabel)")
        .accessibilityValue(accessibilityValue)
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

    private var accessibilityValue: String {
        let state = isEnabled ? "enabled" : "disabled"
        let assignment = holdAssignment.map {
            holdMode == .layers ? "layer \($0)" : "modifier \(modifierDisplay(for: $0))"
        } ?? "no hold assignment"
        let selection = isSelected ? ", selected" : ""
        return "\(state), \(assignment)\(selection)"
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

    private var isPreviewActive: Bool {
        isEnabled && timingPreviewPhase != .idle
    }

    private var previewBackgroundColor: Color {
        guard isPreviewActive else { return backgroundColor }
        switch timingPreviewPhase {
        case .idle: return backgroundColor
        case .pressing: return Color.accentColor.opacity(0.15)
        case .modifier: return Color.accentColor
        }
    }

    private var previewTextColor: Color {
        guard isPreviewActive else { return textColor }
        switch timingPreviewPhase {
        case .idle: return textColor
        case .pressing: return .primary
        case .modifier: return .white
        }
    }

    private var previewBorderColor: Color {
        guard isPreviewActive else { return borderColor }
        return Color.accentColor
    }

    private var previewScaleX: CGFloat {
        if isPreviewActive, timingPreviewPhase == .pressing {
            return 1.03
        }
        return isPressed ? 0.97 : (isHovered ? 1.05 : 1.0)
    }

    private var previewScaleY: CGFloat {
        if isPreviewActive, timingPreviewPhase == .pressing {
            return 0.82
        }
        return isPressed ? 0.97 : (isHovered ? 1.05 : 1.0)
    }

    private var previewOffsetY: CGFloat {
        if isPreviewActive, timingPreviewPhase == .pressing {
            return 4
        }
        return 0
    }

    private static let staggerOrder: [Double] = [0.02, 0.10, 0.0, 0.07, 0.12, 0.03, 0.09, 0.05]

    private var staggerDelay: Double {
        Self.staggerOrder[timingPreviewIndex % Self.staggerOrder.count]
    }
}

private struct HomeRowLayerTargetChip: View {
    let layerName: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: LayerInfo.iconName(for: layerName))
                .font(.caption2.weight(.semibold))
            Text(LayerInfo.displayName(for: layerName))
                .font(.caption2.weight(.semibold))
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
