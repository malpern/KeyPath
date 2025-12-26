import SwiftUI

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

    // Attribution
    let sourceURL: String?

    // MARK: - SwiftUI Colors

    var alphaBaseColor: Color { Color(hex: alphaBase) }
    var alphaLegendColor: Color { Color(hex: alphaLegend) }
    var modBaseColor: Color { Color(hex: modBase) }
    var modLegendColor: Color { Color(hex: modLegend) }
    var accentBaseColor: Color { Color(hex: accentBase) }
    var accentLegendColor: Color { Color(hex: accentLegend) }

    /// Preview colors for swatch display (4 colors: alpha, mod, accent, legend)
    var swatchColors: [Color] {
        [alphaBaseColor, modBaseColor, accentBaseColor, alphaLegendColor]
    }

    // MARK: - Default Colorway

    /// Default colorway matches the original KeyPath overlay colors exactly:
    /// - Background: Color(white: 0.08) = #141414
    /// - Legend: Color(red: 0.88, green: 0.93, blue: 1.0) = #e0edff (slight blue tint)
    static let `default` = GMKColorway(
        id: "default",
        name: "Default",
        designer: "KeyPath",
        year: 2025,
        alphaBase: "#141414", // Color(white: 0.08)
        alphaLegend: "#e0edff", // Slightly blue-tinted white
        modBase: "#141414",
        modLegend: "#e0edff",
        accentBase: "#141414",
        accentLegend: "#e0edff",
        sourceURL: nil
    )

    // MARK: - Top 10 GMK Colorways

    /// All available colorways including default
    static let all: [GMKColorway] = [
        .default,
        .oliviaDark,
        .oliviaLight,
        .gmk8008,
        .laser,
        .redSamurai,
        .botanical,
        .bento,
        .wob,
        .hyperfuse,
        .godspeed,
        .dots
    ]

    /// Find a colorway by ID
    static func find(id: String) -> GMKColorway? {
        all.first { $0.id == id }
    }

    // MARK: - GMK Olivia (Dark)

    // Source: MatrixZJ - RAL 000 20 00 (base), RAL 040 80 20 (legend)

    static let oliviaDark = GMKColorway(
        id: "olivia-dark",
        name: "Olivia Dark",
        designer: "Olivia",
        year: 2018,
        alphaBase: "#2B2B2B", // RAL 000 20 00 (Slate Black)
        alphaLegend: "#F1BEB0", // RAL 040 80 20 (Rose Pink)
        modBase: "#2B2B2B",
        modLegend: "#F1BEB0",
        accentBase: "#F1BEB0",
        accentLegend: "#2B2B2B",
        sourceURL: "https://geekhack.org/index.php?topic=94386.0"
    )

    // MARK: - GMK Olivia (Light)

    // Source: MatrixZJ - CP (base), RAL 040 80 20 (legend)

    static let oliviaLight = GMKColorway(
        id: "olivia-light",
        name: "Olivia Light",
        designer: "Olivia",
        year: 2018,
        alphaBase: "#E1DBD1", // GMK CP (Cream)
        alphaLegend: "#F1BEB0", // RAL 040 80 20 (Rose Pink)
        modBase: "#E1DBD1",
        modLegend: "#F1BEB0",
        accentBase: "#F1BEB0",
        accentLegend: "#E1DBD1",
        sourceURL: "https://geekhack.org/index.php?topic=94386.0"
    )

    // MARK: - GMK 8008

    static let gmk8008 = GMKColorway(
        id: "8008",
        name: "8008",
        designer: "Garrett",
        year: 2019,
        alphaBase: "#939598", // Cool gray
        alphaLegend: "#f5a4b8", // Pink legend
        modBase: "#3c4048", // Dark gray
        modLegend: "#f5a4b8", // Pink legend
        accentBase: "#f5a4b8", // Pink accent
        accentLegend: "#3c4048", // Dark legend
        sourceURL: "https://geekhack.org/index.php?topic=100308.0"
    )

    // MARK: - GMK Laser

    static let laser = GMKColorway(
        id: "laser",
        name: "Laser",
        designer: "MiTo",
        year: 2017,
        alphaBase: "#1a1a2e", // Deep purple-black
        alphaLegend: "#ff2a6d", // Magenta
        modBase: "#1a1a2e",
        modLegend: "#05d9e8", // Cyan
        accentBase: "#ff2a6d", // Magenta accent
        accentLegend: "#1a1a2e",
        sourceURL: "https://mitormk.com/laser"
    )

    // MARK: - GMK Red Samurai

    // Source: MatrixZJ - Pantone 426 C, 7421 C, 465 C

    static let redSamurai = GMKColorway(
        id: "red-samurai",
        name: "Red Samurai",
        designer: "RedSuns",
        year: 2018,
        alphaBase: "#25282A", // Pantone 426 C (Charcoal)
        alphaLegend: "#B9975B", // Pantone 465 C (Gold)
        modBase: "#651D32", // Pantone 7421 C (Burgundy)
        modLegend: "#B9975B", // Pantone 465 C (Gold)
        accentBase: "#651D32", // Burgundy accent
        accentLegend: "#B9975B", // Gold
        sourceURL: "https://geekhack.org/index.php?topic=89970.0"
    )

    // MARK: - GMK Botanical

    // Source: MatrixZJ - Pantone 656 C, 5575 C, 5477 C

    static let botanical = GMKColorway(
        id: "botanical",
        name: "Botanical",
        designer: "Omnitype",
        year: 2020,
        alphaBase: "#DDE5ED", // Pantone 656 C (Pale Blue-Gray)
        alphaLegend: "#92ACA0", // Pantone 5575 C (Sage Green)
        modBase: "#3E5D58", // Pantone 5477 C (Forest Green)
        modLegend: "#92ACA0", // Pantone 5575 C (Sage Green)
        accentBase: "#92ACA0", // Sage green accent
        accentLegend: "#3E5D58", // Forest green
        sourceURL: "https://geekhack.org/index.php?topic=102350.0"
    )

    // MARK: - GMK Bento

    // Source: MatrixZJ - WS4, RAL 240 50 25, custom salmon

    static let bento = GMKColorway(
        id: "bento",
        name: "Bento",
        designer: "Biip",
        year: 2019,
        alphaBase: "#EEE2D0", // GMK WS4 (Warm Cream)
        alphaLegend: "#2A4D69", // Deep Teal Blue
        modBase: "#2A4D69", // Deep Teal Blue
        modLegend: "#EEE2D0", // Warm Cream
        accentBase: "#E87F7F", // Salmon/Coral
        accentLegend: "#2A4D69",
        sourceURL: "https://geekhack.org/index.php?topic=97855.0"
    )

    // MARK: - GMK WoB (White on Black)

    static let wob = GMKColorway(
        id: "wob",
        name: "WoB",
        designer: "GMK",
        year: 2015,
        alphaBase: "#1a1a1a", // Pure black
        alphaLegend: "#ffffff", // Pure white
        modBase: "#1a1a1a",
        modLegend: "#ffffff",
        accentBase: "#1a1a1a",
        accentLegend: "#ffffff",
        sourceURL: "https://www.gmk.net/shop/en/gmk-cyl-wob-white-on-black-keycaps/fptk5009"
    )

    // MARK: - GMK Hyperfuse

    // Source: MatrixZJ - 2M, 2B, DY, TU2

    static let hyperfuse = GMKColorway(
        id: "hyperfuse",
        name: "Hyperfuse",
        designer: "BunnyLake",
        year: 2015,
        alphaBase: "#C6C9C7", // GMK 2M (Medium Gray)
        alphaLegend: "#5D437E", // GMK DY (Purple)
        modBase: "#727474", // GMK 2B (Dark Gray)
        modLegend: "#00A4A9", // GMK TU2 (Teal)
        accentBase: "#00A4A9", // Teal accent
        accentLegend: "#5D437E", // Purple
        sourceURL: "https://geekhack.org/index.php?topic=68198.0"
    )

    // MARK: - GMK Godspeed

    static let godspeed = GMKColorway(
        id: "godspeed",
        name: "Godspeed",
        designer: "MiTo",
        year: 2017,
        alphaBase: "#f5e6c8", // Cream/beige
        alphaLegend: "#3a6ea5", // Blue
        modBase: "#f5e6c8",
        modLegend: "#e8873a", // Orange
        accentBase: "#3a6ea5", // Blue accent
        accentLegend: "#f5e6c8",
        sourceURL: "https://geekhack.org/index.php?topic=84090.0"
    )

    // MARK: - GMK Dots

    static let dots = GMKColorway(
        id: "dots",
        name: "Dots",
        designer: "Biip",
        year: 2019,
        alphaBase: "#f5f5f5", // Light cream
        alphaLegend: "#1a1a1a", // Black dots
        modBase: "#f5f5f5",
        modLegend: "#1a1a1a",
        accentBase: "#ff6b6b", // Coral accent
        accentLegend: "#f5f5f5",
        sourceURL: "https://geekhack.org/index.php?topic=100890.0"
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
