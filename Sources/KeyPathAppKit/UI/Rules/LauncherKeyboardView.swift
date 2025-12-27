import AppKit
import SwiftUI

/// Keyboard visualization for the launcher configuration.
///
/// Shows a visual keyboard with app/website icons on mapped keys.
/// Caps lock shows Hyper star indicator. Unmapped keys appear dimmed.
struct LauncherKeyboardView: View {
    @Binding var config: LauncherGridConfig
    var selectedKey: String?
    var onKeyClicked: (String) -> Void

    /// Physical keyboard layout to use
    private var layout: PhysicalLayout { .macBookUS }

    /// Build mapping lookup from key label to LauncherMapping
    private var mappingsByKey: [String: LauncherMapping] {
        var result: [String: LauncherMapping] = [:]
        for mapping in config.mappings where mapping.isEnabled {
            result[mapping.key.lowercased()] = mapping
        }
        return result
    }

    /// Size of a standard 1u key in points
    private let keyUnitSize: CGFloat = 40
    /// Gap between keys
    private let keyGap: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let scale = calculateScale(for: geometry.size)
            ZStack(alignment: .topLeading) {
                // Render each physical key
                ForEach(layout.keys, id: \.id) { key in
                    // Skip function row and touch ID for cleaner launcher view
                    // We only show main typing area (rows 1-5)
                    if shouldShowKey(key) {
                        keyView(for: key, scale: scale)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    // MARK: - Key Filtering

    /// Only show keys that are relevant for launcher (not function row)
    private func shouldShowKey(_ key: PhysicalKey) -> Bool {
        // Skip function keys (row 0) and touch ID
        // Row 0 has y=0 for esc and function keys
        // Main keyboard rows start at y >= 1.1 (rowSpacing from PhysicalLayout)
        let isFunctionRow = key.y < 1.0
        let isTouchId = key.keyCode == 0xFFFF

        return !isFunctionRow && !isTouchId
    }

    /// Calculate aspect ratio for keyboard (excluding function row)
    private var aspectRatio: CGFloat {
        // Approximate keyboard aspect ratio for main typing area
        // Full MacBook is ~15.5 wide x 6.5 tall (with function row)
        // Main area is ~15.5 wide x 5.5 tall
        15.5 / 5.0
    }

    // MARK: - Key Rendering

    @ViewBuilder
    private func keyView(for key: PhysicalKey, scale: CGFloat) -> some View {
        let keyLabel = key.label.lowercased()
        let mapping = mappingsByKey[keyLabel]
        let isSelected = selectedKey?.lowercased() == keyLabel

        LauncherKeycapView(
            key: key,
            mapping: mapping,
            isSelected: isSelected,
            onTap: {
                onKeyClicked(keyLabel)
            }
        )
        .frame(
            width: keyWidth(for: key, scale: scale),
            height: keyHeight(for: key, scale: scale)
        )
        .position(
            x: keyPositionX(for: key, scale: scale),
            y: keyPositionY(for: key, scale: scale)
        )
    }

    // MARK: - Layout Calculations

    private func calculateScale(for size: CGSize) -> CGFloat {
        // Calculate scale based on visible keyboard area (excluding function row)
        let visibleWidth = layout.totalWidth
        let visibleHeight = layout.totalHeight - 1.1 // Subtract function row height

        let widthScale = size.width / (visibleWidth * (keyUnitSize + keyGap))
        let heightScale = size.height / (visibleHeight * (keyUnitSize + keyGap))
        return min(widthScale, heightScale)
    }

    private func keyWidth(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        (key.width * keyUnitSize + (key.width - 1) * keyGap) * scale
    }

    private func keyHeight(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        (key.height * keyUnitSize + (key.height - 1) * keyGap) * scale
    }

    private func keyPositionX(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        let baseX = key.visualX * (keyUnitSize + keyGap) * scale
        let halfWidth = keyWidth(for: key, scale: scale) / 2
        return baseX + halfWidth + keyGap * scale
    }

    private func keyPositionY(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        // Offset Y to account for hidden function row
        let adjustedY = key.visualY - 1.1 // Subtract function row offset
        let baseY = adjustedY * (keyUnitSize + keyGap) * scale
        let halfHeight = keyHeight(for: key, scale: scale) / 2
        return baseY + halfHeight + keyGap * scale
    }
}

// MARK: - Preview

#Preview("Launcher Keyboard") {
    LauncherKeyboardView(
        config: .constant(LauncherGridConfig.defaultConfig),
        selectedKey: "s",
        onKeyClicked: { key in
            print("Clicked: \(key)")
        }
    )
    .frame(width: 700, height: 250)
    .padding()
    .background(Color(white: 0.1))
}
