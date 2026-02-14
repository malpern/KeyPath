import AppKit
import KeyPathCore
import SwiftUI

/// A read-only keycap for the live overlay.
/// Uses layout roles (based on physical properties) for structure,
/// and optical adjustments (based on label) for visual harmony.
struct OverlayKeycapView: View {
    let key: PhysicalKey
    let baseLabel: String
    let isPressed: Bool
    /// Scale factor from keyboard resize (1.0 = default size)
    let scale: CGFloat
    /// Whether dark mode is active (for backlight glow)
    var isDarkMode: Bool = false
    /// Whether caps lock is engaged (for indicator light)
    var isCapsLockOn: Bool = false
    /// Fade amount: 0 = fully visible, 1 = fully faded
    var fadeAmount: CGFloat = 0
    /// Whether this is a per-key release fade (vs global overlay fade)
    var isReleaseFading: Bool = false
    /// Current layer name for Touch ID key display
    var currentLayerName: String = "base"
    /// Whether layer mapping is loading (shows spinner on Touch ID key)
    var isLoadingLayerMap: Bool = false
    /// Layer-specific key info (what this key does in current layer)
    var layerKeyInfo: LayerKeyInfo?
    /// Whether this key is emphasized (highlighted with accent color for layer hints)
    var isEmphasized: Bool = false
    /// Whether this key has an active one-shot modifier (temporary highlight)
    var isOneShot: Bool = false
    /// Hold label to display when tap-hold key is in hold state
    var holdLabel: String?
    /// Idle label to display for tap-hold inputs when not pressed
    var tapHoldIdleLabel: String?
    /// Callback when key is clicked (not dragged)
    var onKeyClick: ((PhysicalKey, LayerKeyInfo?) -> Void)?
    /// GMK colorway for keycap styling
    var colorway: GMKColorway = .default
    /// Layout total width for rainbow gradient calculation (default 15 for standard keyboards)
    var layoutTotalWidth: CGFloat = 15.0
    /// Whether to hide alpha labels (used when floating labels handle animation)
    var useFloatingLabels: Bool = false
    /// Whether to show scooped/dished home row keys (Kinesis style)
    var showScoopedHomeRow: Bool = false
    /// Whether this key is selected in the mapper drawer (shows selection highlight)
    var isSelected: Bool = false
    /// Whether this key is being hovered in the rules/launcher list (shows secondary highlight)
    var isHoveredByRule: Bool = false
    /// Whether the inspector/drawer is visible (determines click vs drag behavior)
    var isInspectorVisible: Bool = false
    /// Custom icon name set via push-msg (e.g., "arrow-left", "safari")
    var customIcon: String?

    // MARK: - Launcher Mode

    /// Whether launcher mode is active (shows app icons on mapped keys)
    var isLauncherMode: Bool = false
    /// Launcher mapping for this key (nil = no mapping)
    var launcherMapping: LauncherMapping?
    /// Whether we're in a keymap transition window (bypasses remap gating for animation)
    var isKeymapTransitioning: Bool = false

    /// Whether this key has a launcher mapping
    var hasLauncherMapping: Bool {
        launcherMapping != nil
    }

    // MARK: - Layer Mode (Vim/Nav)

    /// Whether we're in a non-base layer (e.g., nav, vim) but not launcher mode
    var isLayerMode: Bool {
        !isLauncherMode && currentLayerName.lowercased() != "base" && currentLayerName.lowercased() != "Base"
    }

    /// Whether this key has a meaningful layer mapping (not transparent/identity)
    var hasLayerMapping: Bool {
        guard let info = layerKeyInfo else { return false }

        // Bottom row modifier keys (fn, ctrl, opt, cmd) should never show as mapped in layer modes
        // They are fundamental modifiers that should look consistent across all layers
        if key.layoutRole == .narrowModifier {
            return false
        }
        // Has a mapping if it's not transparent and has actual content
        if info.isTransparent { return false }
        if info.isLayerSwitch { return true }
        if info.appLaunchIdentifier != nil { return true }
        if info.systemActionIdentifier != nil { return true }
        if info.urlIdentifier != nil { return true }
        // Check if output differs from input (not identity mapping)
        if let outputKey = info.outputKey {
            return outputKey.lowercased() != inputKeyName
        }
        return !info.displayLabel.isEmpty && info.displayLabel.lowercased() != inputKeyName
    }

    /// Whether current layer is a navigation layer
    var isNavLayer: Bool {
        let lower = currentLayerName.lowercased()
        return lower == "nav" || lower == "navigation"
    }

    /// Identity-style mapping: mapped output matches the physical key label
    /// (used to simplify nav layer visuals for explicit identity mappings)
    var isIdentityLayerMapping: Bool {
        guard let info = layerKeyInfo else { return false }
        guard info.collectionId != nil else { return false }
        guard !baseLabel.isEmpty else { return false }
        guard info.appLaunchIdentifier == nil,
              info.systemActionIdentifier == nil,
              info.urlIdentifier == nil else { return false }

        let outputMatchesInput = info.outputKey?.lowercased() == inputKeyName
        let displayMatchesInput = !info.displayLabel.isEmpty
            && info.displayLabel.uppercased() == baseLabel.uppercased()
        return outputMatchesInput || displayMatchesInput
    }

    var isNavIdentityMapping: Bool {
        isNavLayer && isIdentityLayerMapping
    }

    /// Size thresholds for typography adaptation
    var isSmallSize: Bool {
        scale < 0.8
    }

    var isLargeSize: Bool {
        scale >= 1.5
    }

    /// Home row keyCodes (A, S, D, F, J, K, L, ;)
    private static let homeRowKeyCodes: Set<UInt16> = [0, 1, 2, 3, 38, 40, 37, 41]

    /// Whether this key is a home row key
    var isHomeRowKey: Bool {
        Self.homeRowKeyCodes.contains(key.keyCode)
    }

    /// Whether this keycap has visible content (not Color.clear)
    /// When floating labels are enabled, standard keys render Color.clear and floating labels handle the content
    var hasVisibleContent: Bool {
        // If floating labels are disabled, always render content
        guard useFloatingLabels else { return true }

        // Special keys always render their own content
        if hasSpecialLabel { return true }

        // If there's a nav overlay symbol, render it (arrow only, letter handled by floating label)
        if navOverlaySymbol != nil { return true }

        // Nav identity mappings render their own centered label
        if isNavIdentityMapping { return true }

        // If key is remapped to a different output, render the label directly
        // (floating labels only exist for base layout characters like A-Z, not for mapped outputs)
        if let info = layerKeyInfo,
           !info.displayLabel.isEmpty,
           info.displayLabel.uppercased() != baseLabel.uppercased() {
            return true
        }

        // Otherwise, content is Color.clear (floating labels handle it)
        return false
    }

    /// The effective label to display (hold label > layer mapping > keymap/physical)
    var effectiveLabel: String {
        // When key is pressed with a hold label, show the hold label
        if isPressed, let holdLabel {
            return holdLabel
        }

        if !isPressed, let tapHoldIdleLabel, shouldShowTapHoldIdleLabel {
            return tapHoldIdleLabel
        }

        guard let info = layerKeyInfo else {
            return baseLabel
        }

        // Empty displayLabel means no meaningful mapping - fall back to base label
        // Exception: if layer explicitly blocked the key, show empty
        if info.displayLabel.isEmpty {
            // Fall back to physical key label (e.g., for number keys that passthrough)
            return baseLabel.isEmpty ? key.label : baseLabel
        }

        if shouldUseBaseLabel, baseLabel != key.label {
            return baseLabel
        }

        return info.displayLabel
    }

    private var shouldShowTapHoldIdleLabel: Bool {
        guard !isLauncherMode else { return false }
        return currentLayerName.lowercased() == "base"
    }

    /// Input key name (kanata/TCP) for identity mapping checks
    var inputKeyName: String {
        OverlayKeyboardView.keyCodeToKanataName(key.keyCode).lowercased()
    }

    /// Whether the overlay should fall back to the base label (keymap or physical)
    var shouldUseBaseLabel: Bool {
        guard let info = layerKeyInfo else { return true }
        if info.isTransparent { return true }
        if info.isLayerSwitch { return false }
        if info.appLaunchIdentifier != nil || info.systemActionIdentifier != nil || info.urlIdentifier != nil {
            return false
        }
        // Prefer mapped labels (including modifier-only outputs like Hyper) when they differ from input.
        if !info.displayLabel.isEmpty, info.displayLabel.lowercased() != inputKeyName {
            return false
        }
        if let outputKey = info.outputKey {
            return outputKey.lowercased() == inputKeyName
        }
        return true
    }

    /// Optical adjustments for current label
    var adjustments: OpticalAdjustments {
        OpticalAdjustments.forLabel(effectiveLabel)
    }

    /// Metadata for current label
    var metadata: LabelMetadata {
        LabelMetadata.forLabel(effectiveLabel)
    }

    /// Whether mouse is hovering over this key
    @State var isHovering = false

    /// Cached app icon for launch actions
    @State var appIcon: NSImage?

    /// Cached favicon for URL actions
    @State var faviconImage: NSImage?

    // MARK: - Tab Transition Animation State

    /// Animation progress for launcher mode transition (0 = standard, 1 = launcher)
    @State var launcherTransition: CGFloat = 0
    /// Whether icon should be visible (delayed appearance)
    @State var iconVisible: Bool = false

    /// Per-key animation variation (0.0 to 1.0) based on distance from home row
    /// Home row keys move first and fastest; keys further away are noticeably slower
    var keyAnimationVariation: CGFloat {
        // Home row is at y ≈ 2 (A, S, D, F, G, H, J, K, L row)
        let homeRowY: CGFloat = 2.0
        let maxDistance: CGFloat = 3.0 // Max rows away from home row

        // Distance from home row (0 = home row, higher = further)
        let homeRowDistance = abs(key.y - homeRowY)
        let distanceFactor = min(homeRowDistance / maxDistance, 1.0)

        // Apply power curve to make the difference more dramatic
        // Home row stays near 0, but each row away jumps more significantly
        let dramaticFactor = pow(distanceFactor, 0.7)

        // Small random noise for organic feel (scaled by distance)
        let noise = sin(CGFloat(key.keyCode) * 0.7 + key.x * 0.3) * 0.08

        // Home row: ~0, row±1: ~0.4, row±2: ~0.7, far rows: ~1.0
        return min(1.0, dramaticFactor + noise * distanceFactor)
    }

    /// Per-key delay in milliseconds (home row: 0ms, far keys: up to 60ms)
    var keyAnimationDelayMs: Int {
        Int(keyAnimationVariation * 60)
    }

    /// Per-key spring response (home row: very snappy 0.18, far keys: slow 0.5)
    var keySpringResponse: CGFloat {
        0.18 + keyAnimationVariation * 0.32
    }

    /// Per-key spring damping (home row: bouncy 0.5, far keys: heavy 0.85)
    var keySpringDamping: CGFloat {
        0.5 + keyAnimationVariation * 0.35
    }

    /// Whether this key has an app launch action
    var hasAppLaunch: Bool {
        layerKeyInfo?.appLaunchIdentifier != nil
    }

    /// Whether this key has a system action
    var hasSystemAction: Bool {
        layerKeyInfo?.systemActionIdentifier != nil
    }

    /// Whether this key has a URL mapping
    var hasURLMapping: Bool {
        layerKeyInfo?.urlIdentifier != nil
    }

    /// SF Symbol icon for system action (resolved via IconResolverService)
    var systemActionIcon: String? {
        guard let actionId = layerKeyInfo?.systemActionIdentifier else { return nil }
        return IconResolverService.shared.systemActionSymbol(for: actionId)
    }

    var body: some View {
        keycapBody
    }
}
