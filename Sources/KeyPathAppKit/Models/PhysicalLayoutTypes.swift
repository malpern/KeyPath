import Foundation

// MARK: - Layout Preferences Keys

/// UserDefaults/AppStorage keys for physical layout preferences
enum LayoutPreferences {
    /// Key for storing the selected physical keyboard layout ID
    static let layoutIdKey = "overlayLayoutId"

    /// Default layout ID when none is set
    static let defaultLayoutId = "macbook-us"

    /// Key for enabling QMK keyboard search (default: true)
    static let qmkSearchEnabledKey = "qmkSearchEnabled"
    /// Default value for QMK search enabled flag
    static let qmkSearchEnabledDefault = true
}

// MARK: - Layout Categories

/// Categories for organizing physical keyboard layouts in the UI
enum LayoutCategory: String, CaseIterable, Identifiable {
    case usStandard = "US Standard"
    case international = "International"
    case ergonomic = "Ergonomic / Split"
    case custom = "Custom"

    var id: String {
        rawValue
    }

    var displayName: String {
        rawValue
    }
}

/// Represents a single physical key on a keyboard layout
struct PhysicalKey: Identifiable, Hashable {
    /// Sentinel keyCode for keys with no macOS equivalent (layer switches, transparent, macros).
    /// Uses 0xFFFF which is outside the valid macOS virtual keyCode range (0x00–0x7F).
    static let unmappedKeyCode: UInt16 = 0xFFFF

    /// Base for placeholder keyCodes assigned to unrecognized keys during QMK import.
    /// Uses 0xF000+ to avoid collision with real macOS keyCodes (0x00–0x7F range).
    /// Range 0xF000–0xFFFE supports up to 4094 placeholder keys per layout.
    static let placeholderKeyCodeBase: UInt16 = 0xF000

    /// Safe placeholder keyCode for a given index, clamped to avoid overflow past unmappedKeyCode.
    static func placeholderKeyCode(for index: Int) -> UInt16 {
        let clamped = UInt16(clamping: min(max(0, index), 0xFFE))
        return placeholderKeyCodeBase + clamped
    }

    let id: UUID
    let keyCode: UInt16 // CGEvent key code (matches KeyboardCapture)
    let label: String // Display label ("A", "Shift", "⌘", "🔅")
    let x: Double // In keyboard units (0-based)
    let y: Double
    let width: Double // 1.0 = standard key
    let height: Double
    let rotation: Double // Rotation in degrees (for ergonomic keyboards)
    let rotationPivotX: Double? // Rotation pivot X (for QMK rotation)
    let rotationPivotY: Double? // Rotation pivot Y (for QMK rotation)

    // MARK: - Multi-Legend Support (JIS/ISO)

    /// Shifted character legend (top position on keycap)
    /// Example: "!" for the "1" key, "@" for "2", etc.
    let shiftLabel: String?

    /// Sub-label for alternate input (front/bottom-right on keycap)
    /// Example: Hiragana characters on JIS keyboards ("ぬ" on "1" key)
    let subLabel: String?

    /// Tertiary label for additional legends (front/bottom-left on keycap)
    /// Example: Additional symbols or alternate character sets
    let tertiaryLabel: String?

    /// Whether this key has multi-legend content requiring special rendering
    var hasMultipleLegends: Bool {
        shiftLabel != nil || subLabel != nil || tertiaryLabel != nil
    }

    init(
        id: UUID = UUID(),
        keyCode: UInt16,
        label: String,
        x: Double,
        y: Double,
        width: Double = 1.0,
        height: Double = 1.0,
        rotation: Double = 0.0,
        rotationPivotX: Double? = nil,
        rotationPivotY: Double? = nil,
        shiftLabel: String? = nil,
        subLabel: String? = nil,
        tertiaryLabel: String? = nil
    ) {
        self.id = id
        self.keyCode = keyCode
        self.label = label
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.rotationPivotX = rotationPivotX
        self.rotationPivotY = rotationPivotY
        self.shiftLabel = shiftLabel
        self.subLabel = subLabel
        self.tertiaryLabel = tertiaryLabel
    }

    /// Computed visual position after applying rotation transform
    /// For keys with rotation, the x/y in QMK format are pre-rotation coordinates
    /// that need to be rotated around the pivot point (rx, ry)
    var visualX: Double {
        guard rotation != 0, let rx = rotationPivotX, let ry = rotationPivotY else {
            return x
        }
        // Translate to pivot origin, rotate, translate back
        let relX = x + width / 2 - rx // Use key center
        let relY = y + height / 2 - ry
        let radians = rotation * .pi / 180
        let rotatedX = relX * cos(radians) - relY * sin(radians)
        return rotatedX + rx - width / 2
    }

    var visualY: Double {
        guard rotation != 0, let rx = rotationPivotX, let ry = rotationPivotY else {
            return y
        }
        // Translate to pivot origin, rotate, translate back
        let relX = x + width / 2 - rx // Use key center
        let relY = y + height / 2 - ry
        let radians = rotation * .pi / 180
        let rotatedY = relX * sin(radians) + relY * cos(radians)
        return rotatedY + ry - height / 2
    }
}
