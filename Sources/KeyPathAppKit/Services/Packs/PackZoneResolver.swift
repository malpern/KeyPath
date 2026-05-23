import SwiftUI

enum PackZoneResolver {
    static func activeZoneColors(
        installedPackIDs: Set<String>,
        layerName: String
    ) -> [UInt16: Color] {
        for packID in installedPackIDs {
            if let colors = zoneColors(for: packID, layerName: layerName) {
                return colors
            }
        }
        return [:]
    }

    struct LayerPreviewConfig {
        /// Per-key target layers: keyCode -> layer name to preview when that key is held
        let targets: [UInt16: String]

        var activatorKeyCodes: Set<UInt16> { Set(targets.keys) }
    }

    static func layerPreviewConfig(
        installedPackIDs: Set<String>
    ) -> LayerPreviewConfig? {
        var merged: [UInt16: String] = [:]
        for packID in installedPackIDs {
            if let config = previewConfig(for: packID) {
                merged.merge(config.targets) { _, new in new }
            }
        }
        return merged.isEmpty ? nil : LayerPreviewConfig(targets: merged)
    }

    static func activeZoneSubtitles(
        installedPackIDs: Set<String>,
        layerName: String
    ) -> [UInt16: String] {
        for packID in installedPackIDs {
            if let subs = zoneSubtitles(for: packID, layerName: layerName) {
                return subs
            }
        }
        return [:]
    }

    private static func zoneSubtitles(
        for packID: String,
        layerName: String
    ) -> [UInt16: String]? {
        switch packID {
        case PackRegistry.vallackSystem.id:
            let lower = layerName.lowercased()
            if lower.contains("vallack-nav") { return VallackZoneMap.navSubtitles }
            if lower == "base" { return VallackZoneMap.homeSubtitles }
            return nil
        default:
            return nil
        }
    }

    private static func zoneColors(
        for packID: String,
        layerName: String
    ) -> [UInt16: Color]? {
        switch packID {
        case PackRegistry.vallackSystem.id:
            return VallackZoneMap.zones(forLayer: layerName)?.mapValues(\.color)
        default:
            return nil
        }
    }

    private static func previewConfig(for packID: String) -> LayerPreviewConfig? {
        switch packID {
        case PackRegistry.vallackSystem.id:
            let targets = Dictionary(
                uniqueKeysWithValues: VallackZoneMap.activatorKeyCodes.map { ($0, "vallack-nav") }
            )
            return LayerPreviewConfig(targets: targets)
        default:
            return nil
        }
    }
}
