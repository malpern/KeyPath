import SwiftUI

/// Centralized color palette for KeyPath UI.
///
/// Overlay and HUD colors render on controlled dark backgrounds and do NOT
/// adapt to system appearance. Regular app window colors use semantic SwiftUI
/// colors or adapt via `colorScheme`.
enum KeyPathColors {
    // MARK: - Keycap Text

    /// Primary keycap label color — light blue-white for dark keycap backgrounds
    static let keycapText = Color(red: 0.88, green: 0.93, blue: 1.0)

    // MARK: - Layer State Colors (Overlay/HUD)

    /// Orange — Vim layer, default layer mode, hold-active state
    static let layerOrange = Color(red: 0.85, green: 0.45, blue: 0.15)

    /// Green — Vallack navigation, "ready" state
    static let layerGreen = Color(red: 0.2, green: 0.7, blue: 0.4)

    /// Steel blue — Neovim terminal layer
    static let layerBlue = Color(red: 0.3, green: 0.6, blue: 0.9)

    /// Teal — tap-hold active state, launcher/apps
    static let layerTeal = Color(red: 0.2, green: 0.7, blue: 0.8)

    /// Purple — window management & spaces
    static let layerPurple = Color(red: 0.55, green: 0.45, blue: 0.85)

    // MARK: - Overlay Keycap Backgrounds

    /// Dark keycap resting state
    static let keycapDark = Color(red: 56 / 255, green: 56 / 255, blue: 57 / 255)

    /// Dark blue-gray keycap background for mapped keys
    static let keycapMapped = Color(red: 0.15, green: 0.35, blue: 0.45)

    // MARK: - Glow Effects

    /// Light blue glow for active/selected keycaps
    static let keycapGlow = Color(red: 0.6, green: 0.8, blue: 1.0)

    // MARK: - HUD Hint Bubble

    /// Text color for the hide-hint bubble (normal state)
    static let hintText = Color(red: 0.4, green: 0.8, blue: 1.0)

    /// Background for the hide-hint bubble (normal state)
    static let hintBackground = Color(red: 0.1, green: 0.28, blue: 0.45)

    /// Text color for the hide-hint bubble (pressed state)
    static let hintTextPressed = Color(red: 0.6, green: 0.95, blue: 1.0)

    /// Background for the hide-hint bubble (pressed state)
    static let hintBackgroundPressed = Color(red: 0.15, green: 0.45, blue: 0.7)

    // MARK: - Vim Hint Categories

    enum VimHint {
        static let movement = Color(red: 0.4, green: 0.75, blue: 0.45)
        static let wordMotion = Color(red: 0.35, green: 0.65, blue: 0.85)
        static let lineMotion = Color(red: 0.65, green: 0.5, blue: 0.82)
        static let enterInsert = Color(red: 0.9, green: 0.55, blue: 0.4)
        static let edit = Color(red: 0.9, green: 0.7, blue: 0.3)
        static let operators = Color(red: 0.85, green: 0.4, blue: 0.4)
        static let findChar = Color(red: 0.4, green: 0.72, blue: 0.7)
        static let page = Color(red: 0.55, green: 0.6, blue: 0.75)
        static let match = Color(red: 0.7, green: 0.6, blue: 0.5)
        static let search = Color(red: 0.75, green: 0.6, blue: 0.35)
    }

    // MARK: - Splash Screen

    /// Top of splash gradient
    static let splashGradientTop = Color(red: 0x48 / 255.0, green: 0x4C / 255.0, blue: 0x54 / 255.0)

    /// Bottom of splash gradient
    static let splashGradientBottom = Color(red: 0x1D / 255.0, green: 0x1D / 255.0, blue: 0x21 / 255.0)

    // MARK: - Window Controls (standard macOS traffic light colors)

    static let windowClose = Color(red: 0.99, green: 0.35, blue: 0.31)
    static let windowMinimize = Color(red: 0.99, green: 0.77, blue: 0.26)
    static let windowZoom = Color(red: 0.30, green: 0.85, blue: 0.39)
}
