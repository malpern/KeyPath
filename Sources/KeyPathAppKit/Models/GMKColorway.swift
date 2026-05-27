import SwiftUI

// MARK: - Legend Style System

/// How legends are rendered on keycaps
enum LegendStyle: String, Codable, CaseIterable, Identifiable, Equatable {
    case standard // Normal letters/symbols
    case dots // Colored circles instead of text
    case iconMods // Symbols on modifiers (⇧ instead of "shift")
    case blank // No legends at all

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .dots: "Dots"
        case .iconMods: "Icon Mods"
        case .blank: "Blank"
        }
    }
}

/// Configuration for colorway-specific novelty keys
/// These are special keys with unique icons/characters that differ from standard legends
struct NoveltyConfig: Codable, Equatable {
    /// Special character to show on ESC key (e.g., "♥" for Olivia, "侍" for Red Samurai)
    let escNovelty: String?

    /// Special character for Enter key novelty
    let enterNovelty: String?

    /// Use accent color for novelty keys (otherwise uses standard legend color)
    let useAccentColor: Bool

    static let none = NoveltyConfig(escNovelty: nil, enterNovelty: nil, useAccentColor: false)

    /// Check if a key should display a novelty
    func noveltyForKey(label: String) -> String? {
        switch label.lowercased() {
        case "esc", "escape", "⎋": escNovelty
        case "enter", "return", "↩", "↵", "⏎": enterNovelty
        default: nil
        }
    }
}

/// Configuration for the Dots legend style
struct DotsLegendConfig: Codable, Equatable {
    /// How dots are colored across the keyboard
    enum ColorMode: String, Codable, Equatable {
        case monochrome // Single color (uses legend color from colorway)
        case rainbow // Gradient by column (red→purple)
    }

    let colorMode: ColorMode
    let dotSize: CGFloat // Relative to key size (0.18 = 18% of key width)
    let oblongWidthMultiplier: CGFloat // For modifier "bars" (2.5 = 2.5x wider than tall)

    static let `default` = DotsLegendConfig(
        colorMode: .monochrome,
        dotSize: 0.18,
        oblongWidthMultiplier: 2.5
    )

    /// Rainbow colors by column position - GMK standard color codes
    /// Sources: MatrixZJ Color Codes database
    static let rainbowPalette: [String] = [
        "#dd1126", // RO2 - Red
        "#ee6900", // V2 - Orange
        "#ebd400", // GE1 - Yellow
        "#689b34", // AE - Green
        "#0084c2", // N5 - Blue
        "#5D437E" // DY - Purple
    ]

    /// Get dot color for a given column position
    func dotColor(forColumn column: Int, totalColumns: Int, fallbackColor: Color) -> Color {
        switch colorMode {
        case .monochrome:
            return fallbackColor
        case .rainbow:
            guard totalColumns > 0 else { return fallbackColor }
            let normalized = CGFloat(column) / CGFloat(totalColumns - 1)
            let index = Int(normalized * CGFloat(Self.rainbowPalette.count - 1))
            let clampedIndex = max(0, min(index, Self.rainbowPalette.count - 1))
            return Color(hex: Self.rainbowPalette[clampedIndex])
        }
    }
}

/// A GMK keycap colorway definition with hex colors for each key type.
/// Colors sourced from MatrixZJ database and official Geekhack IC threads.
struct GMKColorway: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let designer: String
    let year: Int

    // Core colors (hex strings)
    let alphaBase: String // Alpha key background
    let alphaLegend: String // Alpha key legend
    let modBase: String // Modifier key background
    let modLegend: String // Modifier key legend
    let accentBase: String // Accent key background (if any)
    let accentLegend: String // Accent key legend

    /// Attribution
    let sourceURL: String?

    // Legend style configuration
    let legendStyle: LegendStyle
    let dotsConfig: DotsLegendConfig?
    let noveltyConfig: NoveltyConfig

    // MARK: - SwiftUI Colors

    var alphaBaseColor: Color {
        Color(hex: alphaBase)
    }

    var alphaLegendColor: Color {
        Color(hex: alphaLegend)
    }

    var modBaseColor: Color {
        Color(hex: modBase)
    }

    var modLegendColor: Color {
        Color(hex: modLegend)
    }

    var accentBaseColor: Color {
        Color(hex: accentBase)
    }

    var accentLegendColor: Color {
        Color(hex: accentLegend)
    }

    /// Preview colors for swatch display (4 colors: alpha, mod, accent, legend)
    var swatchColors: [Color] {
        [alphaBaseColor, modBaseColor, accentBaseColor, alphaLegendColor]
    }

    // MARK: - Catalog

    /// All available colorways loaded from bundled JSON
    static let all: [GMKColorway] = {
        guard let url = KeyPathAppKitResources.url(forResource: "colorways", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let colorways = try? JSONDecoder().decode([GMKColorway].self, from: data)
        else {
            #if DEBUG
                print("GMKColorway: Failed to load colorways from JSON, using fallback default")
            #endif
            return [.fallbackDefault]
        }
        return colorways
    }()

    /// Default colorway (first in catalog)
    static let `default`: GMKColorway = all.first { $0.id == "default" } ?? .fallbackDefault

    /// Find a colorway by ID
    static func find(id: String) -> GMKColorway? {
        all.first { $0.id == id }
    }

    /// Hardcoded fallback in case JSON loading fails
    private static let fallbackDefault = GMKColorway(
        id: "default",
        name: "Default",
        designer: "KeyPath",
        year: 2025,
        alphaBase: "#141414",
        alphaLegend: "#e0edff",
        modBase: "#141414",
        modLegend: "#e0edff",
        accentBase: "#141414",
        accentLegend: "#e0edff",
        sourceURL: nil,
        legendStyle: .standard,
        dotsConfig: nil,
        noveltyConfig: .none
    )
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
