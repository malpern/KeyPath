import AppKit
import KeyPathCore
import SwiftUI

// MARK: - BaseKeycap

/// Renders base-layer keycap content (everything except launcher mode, layer mode, and touchId).
/// Extracted from OverlayKeycapView to reduce view complexity.
struct BaseKeycap: View {
    let key: PhysicalKey
    let baseLabel: String
    let scale: CGFloat
    let foregroundColor: Color
    let colorway: GMKColorway
    let layerKeyInfo: LayerKeyInfo?
    let holdLabel: String?
    let tapHoldIdleLabel: String?
    let useFloatingLabels: Bool
    let shiftLabelOverride: String?
    let isPressed: Bool
    let currentLayerName: String
    let isLauncherMode: Bool
    let isLayerMode: Bool
    let isKeymapTransitioning: Bool
    let appIcon: NSImage?
    let faviconImage: NSImage?
    let systemActionIcon: String?
    let zoneSubtitle: String?
    let isLoadingLayerMap: Bool
    let isCapsLockOn: Bool
    let isInlineLayer: Bool
    let hasLayerMapping: Bool

    // MARK: - Body (Content Routing)

    var body: some View {
        if key.hasMultipleLegends {
            multiLegendContent
        } else if hasNoveltyKey {
            noveltyKeyContent
        } else if key.layoutRole == .functionKey {
            functionKeyWithMappingContent
        } else if hasURLMapping {
            urlMappingContent
        } else if hasAppLaunch {
            appLaunchContent
        } else if hasSystemAction {
            systemActionContent
        } else if isInlineLayer, hasLayerMapping, let info = layerKeyInfo {
            inlineLayerMappedContent(info: info)
        } else {
            switch key.layoutRole {
            case .centered:
                centeredContent
            case .bottomAligned:
                bottomAlignedContent
            case .narrowModifier:
                narrowModifierContent
            case .functionKey:
                functionKeyContent
            case .arrow:
                arrowContent
            case .touchId:
                touchIdContent
            case .escKey:
                escKeyContent
            }
        }
    }
}
