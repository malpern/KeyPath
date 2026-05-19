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
        let activatorKeyCodes: Set<UInt16>
        let targetLayer: String
    }

    static func layerPreviewConfig(
        installedPackIDs: Set<String>
    ) -> LayerPreviewConfig? {
        for packID in installedPackIDs {
            if let config = previewConfig(for: packID) {
                return config
            }
        }
        return nil
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
            return LayerPreviewConfig(
                activatorKeyCodes: VallackZoneMap.activatorKeyCodes,
                targetLayer: "vallack-nav"
            )
        default:
            return nil
        }
    }
}
