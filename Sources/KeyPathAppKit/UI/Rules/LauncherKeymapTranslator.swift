import Foundation

/// Translates launcher keys between canonical (QWERTY/kanata) and display labels (logical keymap).
struct LauncherKeymapTranslator {
    let keymap: LogicalKeymap
    let includePunctuation: Bool

    private let displayByCanonical: [String: String]
    private let canonicalByDisplay: [String: String]

    init(keymap: LogicalKeymap, includePunctuation: Bool) {
        self.keymap = keymap
        self.includePunctuation = includePunctuation

        var displayByCanonical: [String: String] = [:]
        var canonicalByDisplay: [String: String] = [:]

        for keyCode in Self.launcherKeyCodes {
            let canonicalKey = OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
            let display = keymap.label(for: keyCode, includeExtraKeys: includePunctuation)
                ?? Self.canonicalFallbackLabel[canonicalKey]
                ?? canonicalKey
            displayByCanonical[canonicalKey] = display
            let displayKey = display.lowercased()
            if canonicalByDisplay[displayKey] == nil {
                canonicalByDisplay[displayKey] = canonicalKey
            }
        }

        self.displayByCanonical = displayByCanonical
        self.canonicalByDisplay = canonicalByDisplay
    }

    init(keymapId: String, includePunctuationStore: String) {
        let resolvedKeymap = LogicalKeymap.find(id: keymapId) ?? .qwertyUS
        let include = KeymapPreferences.includePunctuation(for: keymapId, store: includePunctuationStore)
        self.init(keymap: resolvedKeymap, includePunctuation: include)
    }

    func displayLabel(for canonicalKey: String) -> String {
        displayByCanonical[canonicalKey.lowercased()] ?? canonicalKey
    }

    func canonicalKey(for displayKey: String) -> String? {
        canonicalByDisplay[displayKey.lowercased()]
    }
}

private extension LauncherKeymapTranslator {
    static let launcherKeyCodes: [UInt16] = [
        // Number row + punctuation
        50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24,
        // Top row letters
        12, 13, 14, 15, 17, 16, 32, 34, 31, 35,
        // Home row letters + punctuation
        0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39,
        // Bottom row letters + punctuation
        6, 7, 8, 9, 11, 45, 46, 43, 47, 44,
        // Brackets and backslash
        33, 30, 42
    ]

    static let canonicalFallbackLabel: [String: String] = [
        "semicolon": ";",
        "apostrophe": "'",
        "comma": ",",
        "dot": ".",
        "slash": "/",
        "minus": "-",
        "equal": "=",
        "grave": "`",
        "leftbrace": "[",
        "rightbrace": "]",
        "backslash": "\\"
    ]
}
