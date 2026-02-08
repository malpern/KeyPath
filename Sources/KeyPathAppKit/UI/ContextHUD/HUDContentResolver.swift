import Foundation

/// Resolves which HUD content style to use based on layer context
enum HUDContentResolver {
    /// Determine the content style for a given layer and its key mappings
    /// - Parameters:
    ///   - layerName: The current layer name
    ///   - keyMap: Key code to LayerKeyInfo mapping
    ///   - collections: Enabled rule collections
    /// - Returns: The appropriate content style for the HUD
    static func resolve(
        layerName: String,
        keyMap: [UInt16: LayerKeyInfo],
        collections _: [RuleCollection]
    ) -> HUDContentStyle {
        let normalized = layerName.lowercased()

        // Check by layer name first
        if normalized.contains("window") || normalized.contains("snap") {
            return .windowSnappingGrid
        }

        if normalized == "launcher" {
            return .launcherIcons
        }

        if normalized == "sym" || normalized == "symbol" || normalized == "symbols" {
            return .symbolPicker
        }

        // Check by collection ID - see if the majority of keys belong to a specific collection
        let collectionCounts = countCollections(keyMap: keyMap)

        if collectionCounts[RuleCollectionIdentifier.windowSnapping] ?? 0 > 0 {
            return .windowSnappingGrid
        }

        if collectionCounts[RuleCollectionIdentifier.launcher] ?? 0 > 0 {
            return .launcherIcons
        }

        if collectionCounts[RuleCollectionIdentifier.symbolLayer] ?? 0 > 0 {
            return .symbolPicker
        }

        // Check by key content - if keys have app launch identifiers
        let hasAppLaunches = keyMap.values.contains { $0.appLaunchIdentifier != nil }
        if hasAppLaunches {
            return .launcherIcons
        }

        return .defaultList
    }

    /// Count how many non-transparent keys belong to each collection
    private static func countCollections(keyMap: [UInt16: LayerKeyInfo]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for (_, info) in keyMap where !info.isTransparent {
            if let collectionId = info.collectionId {
                counts[collectionId, default: 0] += 1
            }
        }
        return counts
    }
}
