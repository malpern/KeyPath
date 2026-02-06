import KeyPathCore
import Observation
import SwiftUI

/// View model for the Context HUD, transforming layer key data into grouped entries
@Observable
@MainActor
final class ContextHUDViewModel {
    /// Current layer name displayed in the HUD header
    var layerName: String = ""
    /// Content style determined by the content resolver
    var style: HUDContentStyle = .defaultList
    /// Grouped key entries for the default list view
    var groups: [HUDKeyGroup] = []
    /// Flat list of all entries (for custom views that don't use grouping)
    var allEntries: [HUDKeyEntry] = []

    /// Transform raw layer key data into grouped HUD entries
    /// - Parameters:
    ///   - layerName: The current layer name
    ///   - keyMap: Key code to LayerKeyInfo mapping from LayerKeyMapper
    ///   - collections: All enabled rule collections (for name/color lookup)
    ///   - style: The content style to use
    func update(
        layerName: String,
        keyMap: [UInt16: LayerKeyInfo],
        collections: [RuleCollection],
        style: HUDContentStyle
    ) {
        self.layerName = layerName
        self.style = style

        // Build collection lookup by UUID
        let collectionLookup = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })

        // Filter out transparent keys and build entries
        let entries: [HUDKeyEntry] = keyMap.compactMap { keyCode, info in
            guard !info.isTransparent else { return nil }

            let keycap = keycapLabel(for: keyCode)
            let color = collectionColor(for: info.collectionId)
            let sfSymbol = info.systemActionIdentifier.flatMap {
                IconResolverService.shared.systemActionSymbol(for: $0)
            }

            return HUDKeyEntry(
                keycap: keycap,
                action: info.displayLabel,
                sfSymbol: sfSymbol,
                appIdentifier: info.appLaunchIdentifier,
                urlIdentifier: info.urlIdentifier,
                color: color,
                keyCode: keyCode
            )
        }.sorted { $0.keyCode < $1.keyCode }

        allEntries = entries

        // Group by collection
        var groupMap: [UUID: (name: String, color: Color, entries: [HUDKeyEntry])] = [:]
        let defaultGroupId = UUID()

        for entry in entries {
            // Find the collection ID for this entry's key
            let collectionId = keyMap[entry.keyCode]?.collectionId ?? defaultGroupId
            if groupMap[collectionId] == nil {
                let collection = collectionLookup[collectionId]
                let name = collection?.name ?? "Keys"
                let color = collectionColor(for: collectionId == defaultGroupId ? nil : collectionId)
                groupMap[collectionId] = (name: name, color: color, entries: [])
            }
            groupMap[collectionId]?.entries.append(entry)
        }

        groups = groupMap.values
            .map { HUDKeyGroup(name: $0.name, color: $0.color, entries: $0.entries) }
            .sorted { $0.name < $1.name }
    }

    /// Clear all HUD data
    func clear() {
        layerName = ""
        style = .defaultList
        groups = []
        allEntries = []
    }

    // MARK: - Private Helpers

    /// Convert key code to a display label for the keycap
    private func keycapLabel(for keyCode: UInt16) -> String {
        // Use the same mapping as the overlay keyboard
        let name = OverlayKeyboardView.keyCodeToKanataName(keyCode)
        return name.uppercased()
    }

    /// Get collection color matching the overlay's color scheme
    private func collectionColor(for collectionId: UUID?) -> Color {
        guard let id = collectionId else {
            return Color(red: 0.85, green: 0.45, blue: 0.15) // default orange
        }

        switch id {
        case RuleCollectionIdentifier.vimNavigation:
            return Color(red: 0.85, green: 0.45, blue: 0.15) // orange
        case RuleCollectionIdentifier.windowSnapping:
            return .purple
        case RuleCollectionIdentifier.symbolLayer:
            return .blue
        case RuleCollectionIdentifier.launcher:
            return .cyan
        default:
            return Color(red: 0.85, green: 0.45, blue: 0.15) // default orange
        }
    }
}
