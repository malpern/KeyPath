import SwiftUI

/// A horizontal picker showing the four behavior states using image assets.
/// Place images in Resources/BehaviorIcons/ named:
///   - behavior-tap.png, behavior-tap-selected.png
///   - behavior-hold.png, behavior-hold-selected.png
///   - behavior-doubletap.png, behavior-doubletap-selected.png
///   - behavior-taphold.png, behavior-taphold-selected.png
struct BehaviorStatePicker: View {
    @Binding var selectedState: BehaviorSlot
    var onStateSelected: ((BehaviorSlot) -> Void)?

    /// Whether each state has a configured action
    var configuredStates: Set<BehaviorSlot> = []

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BehaviorSlot.allCases) { slot in
                behaviorStateCell(slot)

                // Divider between cells (not after last)
                if slot != BehaviorSlot.allCases.last {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func behaviorStateCell(_ slot: BehaviorSlot) -> some View {
        let isSelected = selectedState == slot
        let isConfigured = configuredStates.contains(slot)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedState = slot
            }
            onStateSelected?(slot)
        } label: {
            VStack(spacing: 3) {
                // Keycap image (compact)
                behaviorImage(for: slot, isSelected: isSelected)
                    .frame(height: 28)

                // Label (smaller)
                Text(slot.shortLabel)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .lineLimit(1)

                // Configured indicator dot
                Circle()
                    .fill(isConfigured ? Color.accentColor : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .background(
                Group {
                    if isSelected {
                        // Selected state blue glow background
                        RoundedRectangle(cornerRadius: 6)
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
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("behavior-picker-\(slot.rawValue)")
        .accessibilityLabel("\(slot.label)\(isConfigured ? ", configured" : "")")
    }

    @ViewBuilder
    private func behaviorImage(for slot: BehaviorSlot, isSelected: Bool) -> some View {
        let imageName = isSelected ? slot.selectedImageName : slot.imageName

        // Try to load from bundle
        if let image = loadBundleImage(named: imageName) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback to SF Symbol if image not found
            Image(systemName: slot.fallbackIcon)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? .white : .secondary)
        }
    }

    private func loadBundleImage(named name: String) -> NSImage? {
        // Try loading from the bundle's Resources/BehaviorIcons folder
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
                .frame(width: 280)

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
