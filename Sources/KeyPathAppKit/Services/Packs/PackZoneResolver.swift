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
}
