import KeyPathCore
import SwiftUI

// Layout content rendering has moved to BaseKeycap.swift.

extension OverlayKeycapView {
    var navOverlaySymbol: String? {
        guard key.layoutRole == .centered, let info = layerKeyInfo else { return nil }
        let arrowLabels: Set = ["←", "→", "↑", "↓"]
        return arrowLabels.contains(info.displayLabel) ? info.displayLabel : nil
    }

    var zoneSubtitleRenderedInline: Bool {
        guard zoneSubtitle != nil, !isLayerMode, !isLauncherMode else { return false }
        if rendersHomeRowModSubtitle { return true }
        guard colorway.legendStyle == .standard else { return false }
        guard key.layoutRole == .centered else { return false }
        guard navigationSFSymbol == nil else { return false }
        guard navOverlaySymbol == nil else { return false }
        guard metadata.shiftSymbol == nil || isNumpadKey else { return false }
        return true
    }
}
