import Foundation

extension PhysicalLayout {
    // MARK: - MacBook Layouts (Native JSON format)

    /// MacBook US keyboard layout
    /// Layout data loaded from Resources/Keyboards/macbook-us.json
    static let macBookUS: PhysicalLayout = {
        if let layout = PhysicalLayoutLoader.loadFromBundle(filename: "macbook-us") {
            return layout
        }
        print("PhysicalLayout: Failed to load MacBook US from JSON, using fallback")
        return PhysicalLayout(id: "macbook-us", name: "MacBook US", keys: [], totalWidth: 15.54, totalHeight: 6.05)
    }()

    // MARK: - MacBook JIS (Japanese)

    /// MacBook JIS (Japanese Industrial Standard) keyboard layout
    /// Key differences from US: shorter spacebar, L-shaped enter, extra keys for Japanese input
    /// Layout data loaded from Resources/Keyboards/macbook-jis.json
    static let macBookJIS: PhysicalLayout = {
        if let layout = PhysicalLayoutLoader.loadFromBundle(filename: "macbook-jis") {
            return layout
        }
        print("PhysicalLayout: Failed to load MacBook JIS from JSON, using fallback")
        return PhysicalLayout(id: "macbook-jis", name: "MacBook JIS", keys: [], totalWidth: 15.54, totalHeight: 6.05)
    }()

    // MARK: - MacBook ISO

    /// MacBook ISO (International) keyboard layout
    /// Key differences from US: extra IntlBackslash key between Left Shift and Z,
    /// shorter left shift to accommodate the extra key
    /// Layout data loaded from Resources/Keyboards/macbook-iso.json
    static let macBookISO: PhysicalLayout = {
        if let layout = PhysicalLayoutLoader.loadFromBundle(filename: "macbook-iso") {
            return layout
        }
        print("PhysicalLayout: Failed to load MacBook ISO from JSON, using fallback")
        return PhysicalLayout(id: "macbook-iso", name: "MacBook ISO", keys: [], totalWidth: 15.54, totalHeight: 6.05)
    }()

    // MARK: - MacBook ABNT2 (Brazilian)

    /// MacBook ABNT2 (Brazilian Portuguese) keyboard layout
    /// Key differences from ISO:
    /// - Extra key between right shift and slash (the "/" key moves there)
    /// - Shorter right shift to accommodate the extra key
    /// - Extra key on number row (cedilla/acute accent area)
    /// Layout data loaded from Resources/Keyboards/macbook-abnt2.json
    static let macBookABNT2: PhysicalLayout = {
        if let layout = PhysicalLayoutLoader.loadFromBundle(filename: "macbook-abnt2") {
            return layout
        }
        print("PhysicalLayout: Failed to load MacBook ABNT2 from JSON, using fallback")
        return PhysicalLayout(id: "macbook-abnt2", name: "MacBook ABNT2", keys: [], totalWidth: 15.54, totalHeight: 6.05)
    }()

    // MARK: - MacBook Korean (KS)

    /// MacBook Korean Standard keyboard layout
    /// Similar to ANSI but with Han/Eng toggle key and different spacebar arrangement
    /// Layout data loaded from Resources/Keyboards/macbook-korean.json
    static let macBookKorean: PhysicalLayout = {
        if let layout = PhysicalLayoutLoader.loadFromBundle(filename: "macbook-korean") {
            return layout
        }
        print("PhysicalLayout: Failed to load MacBook Korean from JSON, using fallback")
        return PhysicalLayout(id: "macbook-korean", name: "MacBook Korean", keys: [], totalWidth: 15.54, totalHeight: 6.05)
    }()

    // MARK: - Kinesis Advantage 360

    /// Kinesis Advantage 360 split ergonomic keyboard layout
    /// Physical layout parsed from: Resources/Keyboards/adv360pro.json
    /// Key mappings (keyCode + label) are embedded in JSON (Tier 1 keyboard)
    /// Optional Swift overrides available via Kinesis360KeyMap.swift for custom behavior
    static let kinesisAdvantage360: PhysicalLayout = {
        // Try to load from bundled JSON first
        // JSON contains keyCode and label for all keys (Tier 1 format)
        // Fallback to Kinesis360KeyMap.keyMapping for any keys missing from JSON
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "adv360pro",
            keyMapping: Kinesis360KeyMap.keyMapping, // Optional override for Tier 1 customization
            idOverride: "kinesis-360",
            nameOverride: "Kinesis Advantage 360"
        ) {
            return layout
        }

        // Fallback to a minimal layout if JSON parsing fails
        // This should never happen in production, but provides graceful degradation
        print("PhysicalLayout: Failed to load Kinesis 360 from JSON, using fallback")
        return PhysicalLayout(
            id: "kinesis-360",
            name: "Kinesis Advantage 360",
            keys: [],
            totalWidth: 18.75,
            totalHeight: 7.25
        )
    }()

    // MARK: - Standard ANSI Layouts (Tier 2)

    /// 40% ANSI keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi40Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-40",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-40",
            nameOverride: "40% ANSI"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 40% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-40",
            name: "40% ANSI",
            keys: [],
            totalWidth: 15.0,
            totalHeight: 5.0
        )
    }()

    /// 60% ANSI keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi60Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-60",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-60",
            nameOverride: "60% ANSI"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 60% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-60",
            name: "60% ANSI",
            keys: [],
            totalWidth: 15.0,
            totalHeight: 5.0
        )
    }()

    /// 65% ANSI keyboard layout (includes arrow keys)
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi65Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-65",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-65",
            nameOverride: "65% ANSI"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 65% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-65",
            name: "65% ANSI",
            keys: [],
            totalWidth: 18.0,
            totalHeight: 5.0
        )
    }()

    /// 75% ANSI keyboard layout (compact function row, no numpad)
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi75Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-75",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-75",
            nameOverride: "75% ANSI"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 75% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-75",
            name: "75% ANSI",
            keys: [],
            totalWidth: 24.0,
            totalHeight: 6.0
        )
    }()

    /// 80% ANSI keyboard layout (TKL - Tenkeyless, full function row, no numpad)
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi80Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-80",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-80",
            nameOverride: "80% ANSI (TKL)"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 80% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-80",
            name: "80% ANSI (TKL)",
            keys: [],
            totalWidth: 24.0,
            totalHeight: 6.0
        )
    }()

    /// 100% ANSI keyboard layout (full size with numpad)
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let ansi100Percent: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ansi-100",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ansi-100",
            nameOverride: "100% ANSI (Full Size)"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load 100% ANSI from JSON, using fallback")
        return PhysicalLayout(
            id: "ansi-100",
            name: "100% ANSI (Full Size)",
            keys: [],
            totalWidth: 24.0,
            totalHeight: 6.0
        )
    }()

    // MARK: - Enthusiast Keyboards (Tier 2)

    /// HHKB (Happy Hacking Keyboard) layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    static let hhkb: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "hhkb",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "hhkb",
            nameOverride: "HHKB (Happy Hacking Keyboard)"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load HHKB from JSON, using fallback")
        return PhysicalLayout(
            id: "hhkb",
            name: "HHKB (Happy Hacking Keyboard)",
            keys: [],
            totalWidth: 17.0,
            totalHeight: 5.0
        )
    }()

    /// Corne (crkbd) split ergonomic keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    /// Split keyboard with 3x6+3 layout (3 rows, 6 columns per half, 3 thumb keys)
    static let corne: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "corne",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "corne",
            nameOverride: "Corne (crkbd)"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load Corne from JSON, using fallback")
        return PhysicalLayout(
            id: "corne",
            name: "Corne (crkbd)",
            keys: [],
            totalWidth: 15.0,
            totalHeight: 5.0
        )
    }()

    /// Sofle split ergonomic keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    /// Split keyboard with 6x4+5 layout (6 columns, 4 rows per half, 5 thumb keys)
    static let sofle: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "sofle",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "sofle",
            nameOverride: "Sofle"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load Sofle from JSON, using fallback")
        return PhysicalLayout(
            id: "sofle",
            name: "Sofle",
            keys: [],
            totalWidth: 15.0,
            totalHeight: 5.0
        )
    }()

    /// Ferris Sweep split ergonomic keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    /// Minimalist split keyboard with 34 keys total (5x3+2 per half)
    static let ferrisSweep: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "ferris-sweep",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "ferris-sweep",
            nameOverride: "Ferris Sweep"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load Ferris Sweep from JSON, using fallback")
        return PhysicalLayout(
            id: "ferris-sweep",
            name: "Ferris Sweep",
            keys: [],
            totalWidth: 12.0,
            totalHeight: 5.0
        )
    }()

    /// Cornix split ergonomic keyboard layout
    /// Physical layout from JSON, key mappings auto-generated from ANSI position table
    /// Split keyboard similar to Corne/Sofle family
    static let cornix: PhysicalLayout = {
        if let layout = QMKLayoutParser.loadFromBundle(
            filename: "cornix",
            keyMapping: ANSIPositionTable.keyMapping,
            idOverride: "cornix",
            nameOverride: "Cornix LP Split Wireless"
        ) {
            return layout
        }
        print("PhysicalLayout: Failed to load Cornix from JSON, using fallback")
        return PhysicalLayout(
            id: "cornix",
            name: "Cornix LP Split Wireless",
            keys: [],
            totalWidth: 15.0,
            totalHeight: 5.0
        )
    }()
}
