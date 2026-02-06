import KeyPathCore
import SwiftUI

// MARK: - Preview

#Preview("Keyboard Row") {
    HStack(spacing: 4) {
        // fn key
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 63, label: "fn", x: 0, y: 5, width: 1.1),
            baseLabel: "fn",
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 50, height: 45)

        // Control
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 59, label: "⌃", x: 1.2, y: 5, width: 1.1),
            baseLabel: "⌃",
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 50, height: 45)

        // Option
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 58, label: "⌥", x: 2.4, y: 5, width: 1.1),
            baseLabel: "⌥",
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 50, height: 45)

        // Command
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 55, label: "⌘", x: 3.6, y: 5, width: 1.35),
            baseLabel: "⌘",
            isPressed: false,
            scale: 1.5
        )
        .frame(width: 60, height: 45)
    }
    .padding()
    .background(Color.black)
}

#Preview("Letter Key") {
    OverlayKeycapView(
        key: PhysicalKey(keyCode: 0, label: "a", x: 0, y: 0),
        baseLabel: "a",
        isPressed: false,
        scale: 1.5,
        isDarkMode: true
    )
    .frame(width: 50, height: 50)
    .padding()
    .background(Color.black)
}

#Preview("Layer Indicator") {
    HStack(spacing: 8) {
        // Base layer (muted)
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 0xFFFF, label: "🔒", x: 14.5, y: 0, width: 1.0),
            baseLabel: "🔒",
            isPressed: false,
            scale: 1.5,
            isDarkMode: true,
            currentLayerName: "base"
        )
        .frame(width: 50, height: 50)

        // Active layer (full opacity)
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 0xFFFF, label: "🔒", x: 14.5, y: 0, width: 1.0),
            baseLabel: "🔒",
            isPressed: false,
            scale: 1.5,
            isDarkMode: true,
            currentLayerName: "nav"
        )
        .frame(width: 50, height: 50)

        // Loading state
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 0xFFFF, label: "🔒", x: 14.5, y: 0, width: 1.0),
            baseLabel: "🔒",
            isPressed: false,
            scale: 1.5,
            isDarkMode: true,
            isLoadingLayerMap: true
        )
        .frame(width: 50, height: 50)
    }
    .padding()
    .background(Color.black)
}

#Preview("Emphasized Keys (HJKL)") {
    HStack(spacing: 8) {
        // Normal key
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 0, label: "a", x: 0, y: 0),
            baseLabel: "a",
            isPressed: false,
            scale: 1.5,
            isDarkMode: true
        )
        .frame(width: 50, height: 50)

        // Emphasized key (vim nav)
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 4, label: "h", x: 0, y: 0),
            baseLabel: "h",
            isPressed: false,
            scale: 1.5,
            isDarkMode: true,
            isEmphasized: true
        )
        .frame(width: 50, height: 50)

        // Emphasized + Pressed
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 38, label: "j", x: 0, y: 0),
            baseLabel: "j",
            isPressed: true,
            scale: 1.5,
            isDarkMode: true,
            isEmphasized: true
        )
        .frame(width: 50, height: 50)

        // Just pressed (not emphasized)
        OverlayKeycapView(
            key: PhysicalKey(keyCode: 40, label: "k", x: 0, y: 0),
            baseLabel: "k",
            isPressed: true,
            scale: 1.5,
            isDarkMode: true
        )
        .frame(width: 50, height: 50)
    }
    .padding()
    .background(Color.black)
}

#Preview("GMK Dots Rainbow") {
    HStack(spacing: 4) {
        // Alpha keys with rainbow dots at different column positions
        ForEach(0 ..< 10, id: \.self) { col in
            OverlayKeycapView(
                key: PhysicalKey(keyCode: UInt16(col), label: String(Character(UnicodeScalar(97 + col)!)), x: CGFloat(col), y: 1),
                baseLabel: String(Character(UnicodeScalar(97 + col)!)),
                isPressed: false,
                scale: 1.5,
                colorway: .dots,
                layoutTotalWidth: 10
            )
            .frame(width: 45, height: 45)
        }
    }
    .padding()
    .background(Color.black)
}

#Preview("GMK Dots Dark Rainbow") {
    VStack(spacing: 4) {
        // Top row with rainbow alphas
        HStack(spacing: 4) {
            ForEach(0 ..< 10, id: \.self) { col in
                OverlayKeycapView(
                    key: PhysicalKey(keyCode: UInt16(col), label: String(col), x: CGFloat(col), y: 0),
                    baseLabel: String(col),
                    isPressed: false,
                    scale: 1.2,
                    colorway: .dotsDark,
                    layoutTotalWidth: 15
                )
                .frame(width: 38, height: 38)
            }
        }
        // Bottom row with modifiers (oblongs)
        HStack(spacing: 4) {
            OverlayKeycapView(
                key: PhysicalKey(keyCode: 59, label: "⌃", x: 0, y: 3, width: 1.5),
                baseLabel: "⌃",
                isPressed: false,
                scale: 1.2,
                colorway: .dotsDark,
                layoutTotalWidth: 15
            )
            .frame(width: 55, height: 38)

            OverlayKeycapView(
                key: PhysicalKey(keyCode: 58, label: "⌥", x: 2, y: 3, width: 1.2),
                baseLabel: "⌥",
                isPressed: false,
                scale: 1.2,
                colorway: .dotsDark,
                layoutTotalWidth: 15
            )
            .frame(width: 45, height: 38)

            OverlayKeycapView(
                key: PhysicalKey(keyCode: 55, label: "⌘", x: 4, y: 3, width: 1.3),
                baseLabel: "⌘",
                isPressed: false,
                scale: 1.2,
                colorway: .dotsDark,
                layoutTotalWidth: 15
            )
            .frame(width: 50, height: 38)

            // Spacebar
            OverlayKeycapView(
                key: PhysicalKey(keyCode: 49, label: " ", x: 6, y: 3, width: 5.0),
                baseLabel: " ",
                isPressed: false,
                scale: 1.2,
                colorway: .dotsDark,
                layoutTotalWidth: 15
            )
            .frame(width: 180, height: 38)
        }
    }
    .padding()
    .background(Color.black)
}
