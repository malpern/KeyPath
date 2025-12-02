import SwiftUI

/// Interactive keyboard view for the simulator.
/// Renders a full keyboard layout with clickable keys.
/// Highlights keys when pressed on physical keyboard.
struct SimulatorKeyboardView: View {
    let layout: PhysicalLayout
    let pressedKeyCodes: Set<UInt16>
    let onKeyTap: (PhysicalKey) -> Void
    let onKeyHold: (PhysicalKey) -> Void

    /// Size of a standard 1u key in points
    private let keyUnitSize: CGFloat = 40
    /// Gap between keys
    private let keyGap: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let scale = calculateScale(for: geometry.size)

            ZStack(alignment: .topLeading) {
                ForEach(layout.keys) { key in
                    SimulatorKeycapView(
                        key: key,
                        isExternallyPressed: pressedKeyCodes.contains(key.keyCode),
                        onTap: { onKeyTap(key) },
                        onHold: { onKeyHold(key) }
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(layout.totalWidth / layout.totalHeight, contentMode: .fit)
    }

    // MARK: - Layout Calculations

    private func calculateScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / (layout.totalWidth * (keyUnitSize + keyGap))
        let heightScale = size.height / (layout.totalHeight * (keyUnitSize + keyGap))
        // Allow keyboard to scale up to fill available space
        return min(widthScale, heightScale)
    }

    private func keyWidth(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        (key.width * keyUnitSize + (key.width - 1) * keyGap) * scale
    }

    private func keyHeight(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        (key.height * keyUnitSize + (key.height - 1) * keyGap) * scale
    }

    private func keyPositionX(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        let baseX = key.x * (keyUnitSize + keyGap) * scale
        let halfWidth = keyWidth(for: key, scale: scale) / 2
        return baseX + halfWidth + keyGap * scale
    }

    private func keyPositionY(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        let baseY = key.y * (keyUnitSize + keyGap) * scale
        let halfHeight = keyHeight(for: key, scale: scale) / 2
        return baseY + halfHeight + keyGap * scale
    }
}

// MARK: - Preview

#Preview {
    SimulatorKeyboardView(
        layout: .macBookUS,
        pressedKeyCodes: [0, 1], // A and S pressed
        onKeyTap: { key in
            print("Tapped: \(key.label)")
        },
        onKeyHold: { key in
            print("Held: \(key.label)")
        }
    )
    .padding()
    .frame(height: 300)
}
