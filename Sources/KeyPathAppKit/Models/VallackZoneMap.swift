import Foundation

enum VallackZoneMap {
    // Q=12, W=13, E=14, U=32, I=34, O=31
    static let modifierKeyCodes: Set<UInt16> = [12, 13, 14, 32, 34, 31]
    // F=3, J=38
    static let activatorKeyCodes: Set<UInt16> = [3, 38]

    static let navMappingKeyCodes: Set<UInt16> = [
        4, 38, 40, 37, 32, 34, 16, 41,
        12, 13, 14, 15, 0, 1, 2, 5, 17, 9,
    ]

    static let homeSubtitles: [UInt16: String] = [
        12: "⌃", 13: "⌥", 14: "⌘",
        32: "⌘", 34: "⌥", 31: "⌃",
    ]

    static let navSubtitles: [UInt16: String] = [
        4: "←", 38: "↓", 40: "↑", 37: "→",
        32: "⌫", 34: "↵", 16: "⌘C", 41: "⌘V",
        12: "⇥", 13: "esc", 14: "◀Tab", 15: "Tab▶",
        0: "⌘⇥", 1: "Home", 2: "End", 5: "camera",
        17: "◀", 9: "▶",
    ]

    static func homeZones() -> [UInt16: KeyboardZone] {
        var zones: [UInt16: KeyboardZone] = [:]
        for code in modifierKeyCodes { zones[code] = .modifier }
        for code in activatorKeyCodes { zones[code] = .activator }
        return zones
    }

    static func navZones() -> [UInt16: KeyboardZone] {
        var zones: [UInt16: KeyboardZone] = [:]
        for code in navMappingKeyCodes { zones[code] = .navMapping }
        return zones
    }

    static func zones(forLayer layerName: String) -> [UInt16: KeyboardZone]? {
        let lower = layerName.lowercased()
        if lower.contains("vallack-nav") {
            return navZones()
        }
        return homeZones()
    }
}
