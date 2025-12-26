import Foundation

struct LogicalKeymap: Identifiable {
    let id: String
    let name: String
    let description: String
    let learnMoreURL: URL
    let iconFilename: String // SVG filename in Resources/Keymaps (without extension)
    let coreLabels: [UInt16: String] // 30-key letter block (always applied)
    let extraLabels: [UInt16: String] // Number row + outer punctuation (toggle)

    func label(for keyCode: UInt16, includeExtraKeys: Bool) -> String? {
        if let label = coreLabels[keyCode] {
            return label
        }
        if includeExtraKeys {
            return extraLabels[keyCode]
        }
        return nil
    }

    func displayLabel(for key: PhysicalKey, includeExtraKeys: Bool) -> String {
        label(for: key.keyCode, includeExtraKeys: includeExtraKeys) ?? key.label
    }

    static let defaultId = "qwerty-us"

    static let all: [LogicalKeymap] = [qwertyUS, colemak, colemakDH, dvorak, workman]

    static func find(id: String) -> LogicalKeymap? {
        all.first { $0.id == id }
    }

    static let qwertyUS: LogicalKeymap = .init(
        id: "qwerty-us",
        name: "QWERTY",
        description: "The standard US layout used on most keyboards.",
        learnMoreURL: URL(string: "https://en.wikipedia.org/wiki/QWERTY")!,
        iconFilename: "QWERTY",
        coreLabels: buildCoreMap(
            top: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            home: ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"],
            bottom: ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"]
        ),
        extraLabels: [:]
    )

    static let colemak: LogicalKeymap = .init(
        id: "colemak",
        name: "Colemak",
        description: "Popular ergonomic layout that keeps many QWERTY shortcuts intact.",
        learnMoreURL: URL(string: "https://colemak.com/")!,
        iconFilename: "Colemak",
        coreLabels: buildCoreMap(
            top: ["q", "w", "f", "p", "g", "j", "l", "u", "y", ";"],
            home: ["a", "r", "s", "t", "d", "h", "n", "e", "i", "o"],
            bottom: ["z", "x", "c", "v", "b", "k", "m", ",", ".", "/"]
        ),
        extraLabels: [:]
    )

    static let colemakDH: LogicalKeymap = .init(
        id: "colemak-dh",
        name: "Colemak-DH",
        description: "Modern ergonomic layout; DH mod reduces lateral reaches while keeping many QWERTY shortcuts.",
        learnMoreURL: URL(string: "https://colemakmods.github.io/mod-dh/")!,
        iconFilename: "Colemak-DH",
        coreLabels: buildCoreMap(
            top: ["q", "w", "f", "p", "b", "j", "l", "u", "y", ";"],
            home: ["a", "r", "s", "t", "g", "m", "n", "e", "i", "o"],
            bottom: ["z", "x", "c", "d", "v", "k", "h", ",", ".", "/"]
        ),
        extraLabels: [:]
    )

    static let workman: LogicalKeymap = .init(
        id: "workman",
        name: "Workman",
        description: "Ergonomic layout optimized for finger travel and comfortable inward rolls.",
        learnMoreURL: URL(string: "https://workmanlayout.org/")!,
        iconFilename: "Workman",
        coreLabels: buildCoreMap(
            top: ["q", "d", "r", "w", "b", "j", "f", "u", "p", ";"],
            home: ["a", "s", "h", "t", "g", "y", "n", "e", "o", "i"],
            bottom: ["z", "x", "m", "c", "v", "k", "l", ",", ".", "/"]
        ),
        extraLabels: [:]
    )

    static let dvorak: LogicalKeymap = .init(
        id: "dvorak",
        name: "Dvorak",
        description: "Classic alternative layout that emphasizes home row usage and hand alternation.",
        learnMoreURL: URL(string: "https://en.wikipedia.org/wiki/Dvorak_keyboard_layout")!,
        iconFilename: "Dvorak",
        coreLabels: buildCoreMap(
            top: ["'", ",", ".", "p", "y", "f", "g", "c", "r", "l"],
            home: ["a", "o", "e", "u", "i", "d", "h", "t", "n", "s"],
            bottom: [";", "q", "j", "k", "x", "b", "m", "w", "v", "z"]
        ),
        extraLabels: [
            KeyCode.grave: "`",
            KeyCode.minus: "[",
            KeyCode.equal: "]",
            KeyCode.leftBracket: "/",
            KeyCode.rightBracket: "=",
            KeyCode.backslash: "\\",
            KeyCode.apostrophe: "-"
        ]
    )

    private static let topRowKeyCodes: [UInt16] = [12, 13, 14, 15, 17, 16, 32, 34, 31, 35]
    private static let homeRowKeyCodes: [UInt16] = [0, 1, 2, 3, 5, 4, 38, 40, 37, 41]
    private static let bottomRowKeyCodes: [UInt16] = [6, 7, 8, 9, 11, 45, 46, 43, 47, 44]

    private static func buildCoreMap(
        top: [String],
        home: [String],
        bottom: [String]
    ) -> [UInt16: String] {
        var map: [UInt16: String] = [:]
        for (code, label) in zip(topRowKeyCodes, top) {
            map[code] = label
        }
        for (code, label) in zip(homeRowKeyCodes, home) {
            map[code] = label
        }
        for (code, label) in zip(bottomRowKeyCodes, bottom) {
            map[code] = label
        }
        return map
    }

    private enum KeyCode {
        static let grave: UInt16 = 50
        static let minus: UInt16 = 27
        static let equal: UInt16 = 24
        static let leftBracket: UInt16 = 33
        static let rightBracket: UInt16 = 30
        static let backslash: UInt16 = 42
        static let apostrophe: UInt16 = 39
    }
}

enum KeymapPreferences {
    static let keymapIdKey = "overlayKeymapId"
    static let includePunctuationStoreKey = "overlayKeymapIncludePunctuation"

    static func includePunctuation(for keymapId: String, store: String) -> Bool {
        let map = decodeIncludeMap(from: store)
        return map[keymapId] ?? false
    }

    static func includePunctuation(for keymapId: String, userDefaults: UserDefaults = .standard) -> Bool {
        includePunctuation(
            for: keymapId,
            store: userDefaults.string(forKey: includePunctuationStoreKey) ?? "{}"
        )
    }

    static func updatedIncludePunctuationStore(
        from store: String,
        keymapId: String,
        includePunctuation: Bool
    ) -> String {
        var map = decodeIncludeMap(from: store)
        map[keymapId] = includePunctuation
        return encodeIncludeMap(map)
    }

    private static func decodeIncludeMap(from store: String) -> [String: Bool] {
        let normalized = store.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let data = normalized.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private static func encodeIncludeMap(_ map: [String: Bool]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(map),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return encoded
    }
}
