import Foundation
import SwiftUI

// MARK: - Layout Roles

/// Determines the layout structure of a keycap based on physical properties.
/// This is separate from the label content, making remapping safe.
enum KeycapLayoutRole {
    /// Standard letter/symbol keys - content centered
    case centered

    /// Wide modifier keys (shift, return, delete, tab, caps) - text at bottom edge
    case bottomAligned

    /// Bottom row narrow modifiers (fn, ctrl, opt, cmd) - symbol centered, optional word below
    case narrowModifier

    /// Function row keys - SF Symbol with small label below
    case functionKey

    /// Arrow keys - small centered symbol
    case arrow

    /// Touch ID / Power button - centered icon
    case touchId

    /// ESC key - bottom-left aligned text
    case escKey
}

// MARK: - Optical Adjustments

/// Per-label optical adjustments for visual harmony.
/// These are purely cosmetic tweaks that don't affect layout structure.
struct OpticalAdjustments {
    /// Font size multiplier (1.0 = default)
    var fontScale: CGFloat = 1.0

    /// Vertical offset to harmonize with neighbors
    var verticalOffset: CGFloat = 0

    /// Font weight override (nil = use default for role)
    var fontWeight: Font.Weight?

    static let `default` = OpticalAdjustments()

    // MARK: - Lookup Table

    /// Optical adjustments by label - purely cosmetic, not layout-affecting
    static func forLabel(_ label: String) -> OpticalAdjustments {
        switch label {
        // Bottom modifiers - optical sizing to match visual weight
        case "⌃": OpticalAdjustments(fontScale: 1.18, verticalOffset: 1.0) // Thin caret needs larger size, nudge down
        case "⌥": OpticalAdjustments(fontScale: 1.09, verticalOffset: 0.5) // Option slightly high
        case "⌘": OpticalAdjustments(fontScale: 1.0, verticalOffset: 0) // Command is visually heavy, balanced
        // Number row - optical baseline alignment
        case "6": OpticalAdjustments(verticalOffset: -1.5) // Nudge up to align with 5, 7
        case "8": OpticalAdjustments(verticalOffset: -1.5) // Nudge up to align with 7, 9
        // Number row shift symbols
        case "^": OpticalAdjustments(fontScale: 1.2) // Caret 20% larger
        case "*": OpticalAdjustments(fontScale: 1.2) // Asterisk 20% larger
        case "@", "#", "$", "%", "&", "(", ")": OpticalAdjustments(fontScale: 0.95) // 5% smaller
        // Dual symbol keys - shift symbols
        case "<", ">": OpticalAdjustments(fontScale: 1.1) // Angle brackets 10% larger
        case "{", "}": OpticalAdjustments(fontScale: 0.85) // Braces 15% smaller
        case "|": OpticalAdjustments(fontScale: 0.85) // Pipe 15% smaller
        case "~": OpticalAdjustments(fontScale: 1.1) // Tilde 10% larger
        case "_": OpticalAdjustments(fontScale: 1.4) // Underscore needs to be larger
        case "+": OpticalAdjustments(fontScale: 0.75) // Plus reduced
        // Dual symbol keys - main symbols
        case "[", "]": OpticalAdjustments(fontScale: 0.85) // Brackets 15% smaller
        case "\\": OpticalAdjustments(fontScale: 0.85) // Backslash 15% smaller
        case "-", "=": OpticalAdjustments(fontScale: 0.7, fontWeight: .light) // Reduced, light
        case "/": OpticalAdjustments(fontScale: 0.9) // Slash 10% smaller
        default: .default
        }
    }
}

// MARK: - PhysicalKey Extension

extension PhysicalKey {
    // MARK: - KeyCode Sets for Role Detection

    /// Function key keyCodes (F1-F12)
    private static let functionKeyCodes: Set<UInt16> = [
        122, // F1
        120, // F2
        99, // F3
        118, // F4
        96, // F5
        97, // F6
        98, // F7
        100, // F8
        101, // F9
        109, // F10
        103, // F11
        111 // F12
    ]

    /// Narrow modifier keyCodes (fn, ctrl, opt, cmd on both sides)
    private static let narrowModifierKeyCodes: Set<UInt16> = [
        63, // fn
        59, // left ctrl
        58, // left opt
        55, // left cmd
        54, // right cmd
        61, // right opt
        62 // right ctrl (if present)
    ]

    /// Layout role determined by keyCode first, then physical properties as fallback.
    /// Using keyCode ensures correct rendering across different keyboard layouts
    /// (e.g., Kinesis 360 vs MacBook) where position-based detection would fail.
    var layoutRole: KeycapLayoutRole {
        // 1. Use keyCode for definitive roles

        // Function keys (F1-F12) by keyCode
        if Self.functionKeyCodes.contains(keyCode) {
            return .functionKey
        }

        // ESC key by keyCode
        if keyCode == 53 {
            return .escKey
        }

        // Touch ID / layer indicator: sentinel keyCode with specific label
        // Only the MacBook Touch ID key (🔒) gets this role
        if keyCode == 0xFFFF, label == "🔒" {
            return .touchId
        }

        // Sentinel keyCode keys without Touch ID label (Kinesis Lyr, Fn, etc.)
        // These should display as centered labels
        if keyCode == 0xFFFF {
            return .centered
        }

        // Narrow modifiers by keyCode (fn, ctrl, opt, cmd)
        if Self.narrowModifierKeyCodes.contains(keyCode) {
            return .narrowModifier
        }

        // 2. Use physical properties for remaining keys

        // Arrow keys: small height (< 0.5)
        if height < 0.5 {
            return .arrow
        }

        // Wide keys: width >= 1.5 (shift, return, delete, tab, caps, spacebar)
        if width >= 1.5 {
            // Spacebar is very wide (> 5 units) - centered content
            if width > 5 {
                return .centered
            }
            return .bottomAligned
        }

        // Everything else: standard centered layout
        return .centered
    }

    /// Whether this is a right-side key (for alignment purposes)
    var isRightSideKey: Bool {
        // Right-side keys based on x position (past center of keyboard)
        x > 7
    }
}

// MARK: - Label Metadata

/// Metadata for specific labels - word expansions, SF Symbols, etc.
struct LabelMetadata {
    /// Word label for wide modifiers (e.g., "⇧" -> "shift")
    var wordLabel: String?

    /// SF Symbol name for function keys
    var sfSymbol: String?

    /// Shift symbol for dual-symbol keys
    var shiftSymbol: String?

    // MARK: - Lookup

    static func forLabel(_ label: String) -> LabelMetadata {
        // Check for labels that start with symbol + space + text (e.g., "⇥ tab")
        // Extract just the symbol part for matching
        let cleanLabel = label.contains(" ") ? String(label.split(separator: " ").first ?? "") : label

        switch cleanLabel {
        // Wide modifiers
        case "⇧": return LabelMetadata(wordLabel: "shift")
        case "↩": return LabelMetadata(wordLabel: "return")
        case "⌫": return LabelMetadata(wordLabel: "delete")
        case "⇥": return LabelMetadata(wordLabel: "tab")
        case "⇪": return LabelMetadata(wordLabel: "caps lock")
        case "⎋": return LabelMetadata(wordLabel: "esc")
        // Bottom modifiers
        case "⌃": return LabelMetadata(wordLabel: "control")
        case "⌥": return LabelMetadata(wordLabel: "option")
        case "⌘": return LabelMetadata(wordLabel: "command")
        // Number row shift symbols
        case "1": return LabelMetadata(shiftSymbol: "!")
        case "2": return LabelMetadata(shiftSymbol: "@")
        case "3": return LabelMetadata(shiftSymbol: "#")
        case "4": return LabelMetadata(shiftSymbol: "$")
        case "5": return LabelMetadata(shiftSymbol: "%")
        case "6": return LabelMetadata(shiftSymbol: "^")
        case "7": return LabelMetadata(shiftSymbol: "&")
        case "8": return LabelMetadata(shiftSymbol: "*")
        case "9": return LabelMetadata(shiftSymbol: "(")
        case "0": return LabelMetadata(shiftSymbol: ")")
        // Dual symbol keys
        case ",": return LabelMetadata(shiftSymbol: "<")
        case ".": return LabelMetadata(shiftSymbol: ">")
        case "/": return LabelMetadata(shiftSymbol: "?")
        case ";": return LabelMetadata(shiftSymbol: ":")
        case "'": return LabelMetadata(shiftSymbol: "\"")
        case "[": return LabelMetadata(shiftSymbol: "{")
        case "]": return LabelMetadata(shiftSymbol: "}")
        case "\\": return LabelMetadata(shiftSymbol: "|")
        case "`": return LabelMetadata(shiftSymbol: "~")
        case "-": return LabelMetadata(shiftSymbol: "_")
        case "=": return LabelMetadata(shiftSymbol: "+")
        default: return LabelMetadata()
        }
    }

    /// SF Symbol lookup by keyCode (more reliable than label for function keys)
    static func sfSymbol(forKeyCode keyCode: UInt16) -> String? {
        switch keyCode {
        case 122: "sun.min" // F1
        case 120: "sun.max" // F2
        case 99: "rectangle.3.group" // F3
        case 118: "magnifyingglass" // F4
        case 96: "mic" // F5
        case 97: "moon" // F6
        case 98: "backward" // F7
        case 100: "playpause" // F8
        case 101: "forward" // F9
        case 109: "speaker.slash" // F10
        case 103: "speaker.wave.1" // F11
        case 111: "speaker.wave.3" // F12
        default: nil
        }
    }

    /// SF Symbol lookup by simulator output name (e.g., "VolUp" -> "speaker.wave.3")
    /// Used when a key is remapped to a media/system action
    static func sfSymbol(forOutputLabel label: String) -> String? {
        // Strip layer suffix like "[base layer]" that Mapper adds to notes
        let cleanLabel = label.replacingOccurrences(
            of: #"\s*\[[^\]]+\s+layer\]$"#,
            with: "",
            options: .regularExpression
        )
        switch cleanLabel {
        // Media keys (simulator canonical names from keyberon KeyCode enum)
        case "MediaPlayPause", "pp": return "playpause"
        case "MediaNextSong", "next": return "forward"
        case "MediaPreviousSong", "prev": return "backward"
        // Volume keys (simulator outputs Mute/VolUp/VolDown)
        case "Mute", "MediaMute", "mute": return "speaker.slash"
        case "VolUp", "volu": return "speaker.wave.3"
        case "VolDown", "voldwn", "vold": return "speaker.wave.1"
        // Brightness keys
        case "BrightnessUp", "brup": return "sun.max"
        case "BrightnessDown", "brdn": return "sun.min"
        // System actions (Do Not Disturb, etc.)
        case "Do Not Disturb": return "moon"
        case "Spotlight": return "magnifyingglass"
        case "Mission Control": return "rectangle.3.group"
        case "Launchpad": return "square.grid.3x3"
        case "Dictation": return "mic"
        case "Siri": return "waveform.circle"
        case "Notification Center": return "bell"
        // macOS system hotkey combos (from Mapper saving system actions as chords)
        // These are the standard macOS keyboard shortcuts for function key actions
        case "⌃⇧⌘Z": return "magnifyingglass" // Spotlight (Cmd+Ctrl+Shift+Z placeholder - actual key varies)
        case "⌃⌘F": return "rectangle.3.group" // Mission Control
        case "⌃⌘L": return "square.grid.3x3" // Launchpad
        default: return nil
        }
    }
}
