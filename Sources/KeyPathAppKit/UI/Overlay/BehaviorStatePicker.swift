import SwiftUI

/// A horizontal picker showing the behavior states using image assets.
/// Flat controls with click feedback and configuration indicators.
/// Place images in Resources/BehaviorIcons/ named:
///   - behavior-tap.png, behavior-tap-selected.png
///   - behavior-hold.png, behavior-hold-selected.png
///   - behavior-combo.png, behavior-combo-selected.png
struct BehaviorStatePicker: View {
    @Binding var selectedState: BehaviorSlot

    /// Whether each state has a configured action (for hold, combo)
    var configuredStates: Set<BehaviorSlot> = []

    /// Whether the tap behavior is non-identity (A→B, not A→A)
    /// When true, shows the "in use" dot for tap
    var tapIsNonIdentity: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            ForEach(BehaviorSlot.allCases) { slot in
                BehaviorStateCell(
                    slot: slot,
                    isSelected: selectedState == slot,
                    isConfigured: isSlotConfigured(slot),
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedState = slot
                        }
                    }
                )
            }
        }
    }

    /// Determine if a slot should show the "in use" dot
    private func isSlotConfigured(_ slot: BehaviorSlot) -> Bool {
        switch slot {
        case .tap:
            // Only show dot if tap is a non-identity mapping (A→B, not A→A)
            tapIsNonIdentity
        case .hold, .combo:
            // Show dot if the slot has a configured action
            configuredStates.contains(slot)
        }
    }
}

/// Individual behavior state cell with press feedback
private struct BehaviorStateCell: View {
    let slot: BehaviorSlot
    let isSelected: Bool
    let isConfigured: Bool
    let onSelect: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 3) {
                // Keycap image (25% larger: 28 -> 35)
                behaviorImage
                    .frame(height: 35)

                // Label centered, with configured dot as overlay
                Text(slot.shortLabel)
                    .font(.system(size: 9, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
                    .overlay(alignment: .leading) {
                        // Configured indicator dot (positioned to the left of label)
                        Circle()
                            .fill(isConfigured ? Color.accentColor : Color.clear)
                            .frame(width: 5, height: 5)
                            .offset(x: -8)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BehaviorCellButtonStyle(isPressed: $isPressed))
        .accessibilityIdentifier("behavior-picker-\(slot.rawValue)")
        .accessibilityLabel("\(slot.label)\(isConfigured ? ", configured" : "")")
    }

    @ViewBuilder
    private var behaviorImage: some View {
        let imageName = isSelected ? slot.selectedImageName : slot.imageName

        // Try to load from bundle
        if let image = loadBundleImage(named: imageName) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback to custom keycap illustration
            BehaviorKeycapIcon(slot: slot, isSelected: isSelected)
        }
    }

    private func loadBundleImage(named name: String) -> NSImage? {
        // Resources are at bundle root (process() flattens subdirectories)
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "png"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

// MARK: - Custom Keycap Icons for Behavior States

/// Custom-drawn keycap icons that illustrate each behavior state
private struct BehaviorKeycapIcon: View {
    let slot: BehaviorSlot
    let isSelected: Bool

    private var strokeColor: Color {
        isSelected ? Color.accentColor : Color.secondary.opacity(0.6)
    }

    private var fillColor: Color {
        isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)
    }

    var body: some View {
        Group {
            switch slot {
            case .tap:
                tapIcon
            case .hold:
                holdIcon
            case .combo:
                comboIcon
            }
        }
        .frame(width: 28, height: 28)
    }

    /// Tap: Single keycap with downward arrow
    private var tapIcon: some View {
        ZStack {
            // Keycap
            RoundedRectangle(cornerRadius: 4)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(strokeColor, lineWidth: 1.5)
                )
                .frame(width: 18, height: 16)

            // Downward press indicator
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(strokeColor)
                .offset(y: 1)
        }
    }

    /// Hold: Keycap with hold bar underneath
    private var holdIcon: some View {
        VStack(spacing: 2) {
            // Keycap (pressed appearance)
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(strokeColor, lineWidth: 1.5)
                )
                .frame(width: 18, height: 14)

            // Hold duration bar
            RoundedRectangle(cornerRadius: 1)
                .fill(strokeColor)
                .frame(width: 14, height: 3)
        }
    }

    /// Combo: Two overlapping keycaps (keys pressed together)
    private var comboIcon: some View {
        HStack(spacing: -6) {
            // Left keycap
            RoundedRectangle(cornerRadius: 3)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(strokeColor, lineWidth: 1.5)
                )
                .frame(width: 14, height: 16)

            // Right keycap (overlapping)
            RoundedRectangle(cornerRadius: 3)
                .fill(fillColor.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(strokeColor, lineWidth: 1.5)
                )
                .frame(width: 14, height: 16)
        }
    }
}

/// Button style with press feedback animation
private struct BehaviorCellButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

// MARK: - BehaviorSlot Image Names

extension BehaviorSlot {
    var imageName: String {
        switch self {
        case .tap: "behavior-tap"
        case .hold: "behavior-hold"
        case .combo: "behavior-combo"
        }
    }

    var selectedImageName: String {
        switch self {
        case .tap: "behavior-tap-selected"
        case .hold: "behavior-hold-selected"
        case .combo: "behavior-combo-selected"
        }
    }

    var fallbackIcon: String {
        switch self {
        case .tap: "rectangle.portrait.arrowtriangle.2.inward"
        case .hold: "rectangle.portrait.bottomhalf.filled"
        case .combo: "rectangle.portrait.on.rectangle.portrait"
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Behavior State Picker") {
        struct PreviewWrapper: View {
            @State var selected: BehaviorSlot = .tap

            var body: some View {
                VStack(spacing: 20) {
                    BehaviorStatePicker(
                        selectedState: $selected,
                        configuredStates: [.hold],
                        tapIsNonIdentity: true
                    )
                    .frame(width: 240)

                    Text("Selected: \(selected.label)")
                        .foregroundStyle(.white)
                }
                .padding(30)
                .background(Color.black)
            }
        }

        return PreviewWrapper()
    }
#endif
