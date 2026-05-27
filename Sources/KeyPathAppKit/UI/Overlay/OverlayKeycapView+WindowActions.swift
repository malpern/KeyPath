import SwiftUI

extension OverlayKeycapView {
    func windowActionColor(from label: String) -> Color? {
        KeycapSymbols.windowActionColor(from: label, layerName: currentLayerName)
    }

    func windowActionSymbol(from label: String) -> String? {
        KeycapSymbols.windowActionSymbol(from: label, layerName: currentLayerName)
    }
}
