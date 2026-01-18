import SwiftUI

/// A horizontal picker showing the four behavior states using image assets.
/// Flat controls with click feedback and configuration indicators.
/// Place images in Resources/BehaviorIcons/ named:
///   - behavior-tap.png, behavior-tap-selected.png
///   - behavior-hold.png, behavior-hold-selected.png
///   - behavior-doubletap.png, behavior-doubletap-selected.png
///   - behavior-taphold.png, behavior-taphold-selected.png
struct BehaviorStatePicker: View {
    @Binding var selectedState: BehaviorSlot

    /// Whether each state has a configured action
    var configuredStates: Set<BehaviorSlot> = []

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BehaviorSlot.allCases) { slot in
                BehaviorStateCell(
                    slot: slot,
                    isSelected: selectedState == slot,
                    isConfigured: configuredStates.contains(slot),
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedState = slot
                        }
                    }
                )

                // Divider between cells (not after last)
                if slot != BehaviorSlot.allCases.last {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            VStack(spacing: 2) {
                // Keycap image (compact)
                behaviorImage
                    .frame(height: 24)

                // Label (smaller)
                Text(slot.shortLabel)
                    .font(.system(size: 8, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .lineLimit(1)

                // Configured indicator dot
                Circle()
                    .fill(isConfigured ? Color.accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
            .background(cellBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(BehaviorCellButtonStyle(isPressed: $isPressed))
        .accessibilityIdentifier("behavior-picker-\(slot.rawValue)")
        .accessibilityLabel("\(slot.label)\(isConfigured ? ", configured" : "")")
    }

    @ViewBuilder
    private var cellBackground: some View {
        if isSelected {
            // Selected state blue glow background
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.5),
                            Color.blue.opacity(0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
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
            // Fallback to SF Symbol if image not found
            Image(systemName: slot.fallbackIcon)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .white : .secondary)
        }
    }

    private func loadBundleImage(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "BehaviorIcons"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
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
        case .doubleTap: "behavior-doubletap"
        case .tapHold: "behavior-taphold"
        }
    }

    var selectedImageName: String {
        switch self {
        case .tap: "behavior-tap-selected"
        case .hold: "behavior-hold-selected"
        case .doubleTap: "behavior-doubletap-selected"
        case .tapHold: "behavior-taphold-selected"
        }
    }

    var fallbackIcon: String {
        switch self {
        case .tap: "hand.tap"
        case .hold: "hand.point.down.fill"
        case .doubleTap: "2.circle"
        case .tapHold: "arrow.right.circle"
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
                    configuredStates: [.tap, .hold]
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
