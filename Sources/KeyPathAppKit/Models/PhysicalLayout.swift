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
            // Determine keycode mapping type from variant
            let keyMappingType: KeyMappingType = if let variant = storedLayout.layoutVariant?.lowercased(), variant.contains("iso") {
                .iso
            } else {
                .ansi
            }

            // Choose keycode mapping function
            let keyMapping: (Int, Int) -> (keyCode: UInt16, label: String)? = switch keyMappingType {
            case .ansi:
                ANSIPositionTable.keyMapping(row:col:)
            case .iso:
                ISOPositionTable.keyMapping(row:col:)
            }

            // Re-parse the layout from stored JSON
            guard let layout = QMKLayoutParser.parse(
                data: storedLayout.layoutJSON,
                keyMapping: keyMapping,
                idOverride: "custom-\(storedLayout.id)",
                nameOverride: storedLayout.name
            ) else {
                return nil
            }

            return layout
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
}
