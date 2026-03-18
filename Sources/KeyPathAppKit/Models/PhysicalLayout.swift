import Foundation

/// Represents a complete physical keyboard layout
struct PhysicalLayout: Identifiable {
    let id: String // Unique identifier: "macbook-us", "kinesis-360"
    let name: String // Display name: "MacBook US", "Kinesis Advantage 360"
    let keys: [PhysicalKey]
    let totalWidth: Double // For aspect ratio calculation
    let totalHeight: Double

    /// Initialize with explicit dimensions
    init(id: String, name: String, keys: [PhysicalKey], totalWidth: Double, totalHeight: Double) {
        self.id = id
        self.name = name
        self.keys = keys
        self.totalWidth = totalWidth
        self.totalHeight = totalHeight
    }

    /// Initialize with auto-computed dimensions from keys
    init(id: String, name: String, keys: [PhysicalKey]) {
        self.id = id
        self.name = name
        self.keys = keys

        // Compute dimensions from key positions (using visual positions for rotated keys)
        var maxX = 0.0
        var maxY = 0.0
        for key in keys {
            let keyRight = key.visualX + key.width
            let keyBottom = key.visualY + key.height
            maxX = max(maxX, keyRight)
            maxY = max(maxY, keyBottom)
        }
        totalWidth = maxX
        totalHeight = maxY
    }

    // MARK: - Layout Registry

    /// US Standard layouts (ANSI-based)
    static let usLayouts: [PhysicalLayout] = [
        macBookUS,
        magicKeyboardCompact,
        magicKeyboardTouchID,
        magicKeyboardNumpad,
        magicKeyboardTouchIDNumpad,
        ansi100Percent,
        ansi80Percent,
        ansi75Percent,
        ansi65Percent,
        ansi60Percent,
        ansi40Percent,
        hhkb
    ]

    /// International layouts (ISO, JIS, ABNT2, Korean)
    static let internationalLayouts: [PhysicalLayout] = [
        macBookISO,
        macBookJIS,
        macBookABNT2,
        macBookKorean
    ]

    /// Ergonomic and split keyboards
    static let ergonomicLayouts: [PhysicalLayout] = [
        kinesisAdvantage360,
        kinesisMWave,
        corne,
        sofle,
        ferrisSweep,
        cornix
    ]

    // MARK: - Custom Layouts Cache

    /// Cache for custom layouts to avoid blocking UI thread
    /// Thread-safe using a lock for concurrent access
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var _cachedCustomLayouts: [PhysicalLayout]?
    private nonisolated(unsafe) static var _cacheTimestamp: Date?
    private static let cacheTTL: TimeInterval = 5.0 // 5 second cache TTL

    /// Custom imported layouts (loaded from UserDefaults)
    /// Note: Uses caching to avoid blocking UI thread. Call `invalidateCustomLayoutCache()` after importing.
    static var customLayouts: [PhysicalLayout] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        // Check cache freshness
        if let cached = _cachedCustomLayouts,
           let timestamp = _cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheTTL
        {
            return cached
        }

        // Load custom layouts synchronously from storage
        let store = CustomLayoutStore.load()

        let layouts: [PhysicalLayout] = store.layouts.compactMap { storedLayout -> PhysicalLayout? in
            let layoutId = "custom-\(storedLayout.id)"

            let parsed: PhysicalLayout?

            // Strategy 1: Use cached keymap tokens (best quality)
            if let keymapTokens = storedLayout.defaultKeymap,
               let result = QMKLayoutParser.parseWithKeymap(
                   data: storedLayout.layoutJSON,
                   keymapTokens: keymapTokens,
                   idOverride: layoutId,
                   nameOverride: storedLayout.name
               )
            {
                parsed = result.layout
            }
            // Strategy 2: Position-based parsing (works for any QMK keyboard)
            else if let result = QMKLayoutParser.parseByPositionWithQuality(
                data: storedLayout.layoutJSON,
                idOverride: layoutId,
                nameOverride: storedLayout.name
            ) {
                parsed = result.layout
            }
            // Strategy 3: Matrix-based parsing for bundled keyboards with known matrices
            else {
                let keyMapping: (Int, Int) -> (keyCode: UInt16, label: String)? = if let variant = storedLayout.layoutVariant?.lowercased(), variant.contains("iso") {
                    ISOPositionTable.keyMapping(row:col:)
                } else {
                    ANSIPositionTable.keyMapping(row:col:)
                }

                parsed = QMKLayoutParser.parse(
                    data: storedLayout.layoutJSON,
                    keyMapping: keyMapping,
                    idOverride: layoutId,
                    nameOverride: storedLayout.name
                )
            }

            // Inject drawer key if the layout has layer keys but no drawer button
            return parsed?.withDrawerKeyInjected()
        }

        // Update cache
        _cachedCustomLayouts = layouts
        _cacheTimestamp = Date()

        return layouts
    }

    /// Invalidate the custom layouts cache (call after importing/deleting layouts)
    static func invalidateCustomLayoutCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        _cachedCustomLayouts = nil
        _cacheTimestamp = nil
    }

    /// Registry of all known layouts (US first, then International, then Ergonomic, then Custom)
    // swiftformat:disable:next redundantSelf
    static var all: [PhysicalLayout] {
        usLayouts + internationalLayouts + ergonomicLayouts + customLayouts
    }

    /// Get layouts grouped by category for UI display
    /// Order: US Standard (no header), Ergonomic, International, Custom
    static func layoutsByCategory() -> [(category: LayoutCategory, layouts: [PhysicalLayout])] {
        [
            (.usStandard, usLayouts),
            (.ergonomic, ergonomicLayouts),
            (.international, internationalLayouts),
            (.custom, customLayouts)
        ]
    }

    /// Find a layout by its identifier
    static func find(id: String) -> PhysicalLayout? {
        all.first { $0.id == id }
    }

    /// Whether this layout has a Touch ID key that acts as the drawer toggle
    var hasDrawerButtons: Bool {
        keys.contains { $0.keyCode == PhysicalKey.unmappedKeyCode && $0.label == "🔒" }
    }

    // MARK: - Drawer Key Injection

    /// Whether a label indicates a pure layer-switch key (MO, TG, OSL, DF abbreviations).
    /// These are candidates for drawer key injection. Layer-taps (LT) resolve to their
    /// base key with a real keyCode, so they're naturally excluded.
    static func isLayerKeyLabel(_ label: String) -> Bool {
        guard label.count >= 2, label.count <= 3 else { return false }
        let first = label.first!
        guard "LTD".contains(first) else { return false }
        return label.dropFirst().allSatisfy(\.isNumber)
    }

    /// For QMK-imported layouts without a drawer key, find the best layer key
    /// candidate and convert it to the drawer toggle (🔒).
    ///
    /// Picks the rightmost pure layer-switch key (highest x), breaking ties with
    /// bottom-most (highest y). Layer-taps (LT) that resolve to a base key are
    /// excluded since they're typing keys.
    func withDrawerKeyInjected() -> PhysicalLayout {
        // Already has a drawer button — no injection needed
        guard !hasDrawerButtons else { return self }

        // Only apply to custom/QMK layouts (not built-in)
        guard id.hasPrefix("custom-") else { return self }

        // Find candidate layer keys
        let candidates = keys.enumerated().filter { _, key in
            key.keyCode == PhysicalKey.unmappedKeyCode
                && Self.isLayerKeyLabel(key.label)
        }

        guard let best = candidates.max(by: { a, b in
            if a.element.visualX != b.element.visualX {
                return a.element.visualX < b.element.visualX // rightmost wins
            }
            return a.element.visualY < b.element.visualY // bottom-most breaks ties
        }) else {
            return self // No candidates found
        }

        // Build new keys array with the chosen key's label replaced
        var newKeys = keys
        newKeys[best.offset] = PhysicalKey(
            id: best.element.id,
            keyCode: best.element.keyCode,
            label: "🔒",
            x: best.element.x,
            y: best.element.y,
            width: best.element.width,
            height: best.element.height,
            rotation: best.element.rotation,
            rotationPivotX: best.element.rotationPivotX,
            rotationPivotY: best.element.rotationPivotY,
            shiftLabel: best.element.shiftLabel,
            subLabel: best.element.subLabel,
            tertiaryLabel: best.element.tertiaryLabel
        )

        return PhysicalLayout(id: id, name: name, keys: newKeys, totalWidth: totalWidth, totalHeight: totalHeight)
    }
}
