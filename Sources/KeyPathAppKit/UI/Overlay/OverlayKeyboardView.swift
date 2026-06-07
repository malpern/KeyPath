import AppKit
import KeyPathCore
import SwiftUI

struct EscKeyLeftInsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Keyboard view for the live overlay.
/// Renders a full keyboard layout with keys highlighting based on key codes.
struct OverlayKeyboardView: View {
    let layout: PhysicalLayout
    let keymap: LogicalKeymap
    let includeKeymapPunctuation: Bool
    let pressedKeyCodes: Set<UInt16>
    var isDarkMode: Bool = false
    var fadeAmount: CGFloat = 0 // 0 = fully visible, 1 = fully faded (global overlay fade)
    var currentLayerName: String = "base"
    var isLoadingLayerMap: Bool = false
    /// Key mapping for current layer: keyCode -> LayerKeyInfo
    var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
    /// Physical key codes currently pressed (from Kanata TCP KeyInput, shows physical key not output)
    var effectivePressedKeyCodes: Set<UInt16> = []
    /// Key codes to emphasize (highlight with accent color for layer hints)
    var emphasizedKeyCodes: Set<UInt16> = []
    /// Key codes with active one-shot modifiers (show temporary modifier badge)
    var oneShotKeyCodes: Set<UInt16> = []
    /// Hold labels for tap-hold keys in hold state: keyCode -> display label
    var holdLabels: [UInt16: String] = [:]
    /// Idle labels for tap-hold inputs (show tap output when not pressed)
    var tapHoldIdleLabels: [UInt16: String] = [:]
    /// Keys currently in hold-active state (for orange styling)
    var holdActiveKeyCodes: Set<UInt16> = []
    /// Custom icons for keys set via push-msg: keyCode -> icon name
    var customIcons: [UInt16: String] = [:]
    /// Callback when a key is clicked (not dragged) - selects key in drawer mapper when visible
    var onKeyClick: ((PhysicalKey, LayerKeyInfo?) -> Void)?
    /// Callback when a key is double-clicked in launcher mode (opens edit panel)
    var onKeyDoubleClick: ((PhysicalKey, LayerKeyInfo?) -> Void)?
    /// Key code of currently selected key in mapper drawer (shows selection highlight)
    var selectedKeyCode: UInt16?
    /// Key code being hovered in rules/launcher tabs (for secondary highlight)
    var hoveredRuleKeyCode: UInt16?

    /// Whether the KindaVim hint layer should render on top of the keycap
    /// grid. Driven by the parent (LiveKeyboardOverlayView) from the pack
    /// install state; the layer itself decides per-key visibility from
    /// the live mode + strategy signals.
    var vimHintsActive: Bool = false

    // MARK: - Launcher Mode

    /// Whether launcher mode is active (shows app icons on mapped keys)
    var isLauncherMode: Bool = false
    /// Launcher mappings: key name -> LauncherMapping
    var launcherMappings: [String: LauncherMapping] = [:]
    /// Whether the inspector/drawer is visible (determines click vs drag behavior)
    var isInspectorVisible: Bool = false
    /// Zone coloring from the active system pack (key code -> fill color)
    var activeZoneColors: [UInt16: Color] = [:]
    /// Subtitles from the active system pack (key code -> subtitle string, e.g., "⌃")
    var activeZoneSubtitles: [UInt16: String] = [:]

    // MARK: - Layer Mode (Vim/Nav)

    /// Whether we're in a non-base layer (e.g., nav, vim) but not launcher mode
    private var isLayerMode: Bool {
        !isLauncherMode && !isInlineLayer && currentLayerName.lowercased() != "base"
    }

    private var isInlineLayer: Bool {
        OverlayKeycapView.inlineLayerNames.contains(currentLayerName.lowercased())
    }

    /// Track caps lock state from system
    @State private var isCapsLockOn: Bool = NSEvent.modifierFlags.contains(.capsLock)
    /// Global monitor for flagsChanged events (detects caps lock toggled by kanata/IOKit)
    @State private var flagsChangedMonitor: Any?

    /// Note: keycapFrames removed - we now calculate frames directly from layout
    /// Whether initial render is complete (enables animation for subsequent changes)
    /// Set to true asynchronously after onAppear, so the first render positions keys
    /// without animation, but all subsequent keymap changes animate.
    @State private var initialRenderComplete: Bool = false
    /// Previous keymap ID for detecting changes (used for wobble trigger)
    @State private var previousKeymapId: String = ""
    /// Whether we're in a keymap transition window (bypasses remap gating for animation)
    /// Enables floating labels during keymap switches (QWERTY → Dvorak) even though they're technically remaps
    @State private var isKeymapTransitioning: Bool = false

    /// Cached label-to-keyCode mapping (recomputed when layout/keymap changes)
    @State private var cachedLabelToKeyCode: [String: UInt16] = [:]
    /// Cached floating label pool (recomputed alongside labelToKeyCode)
    @State private var cachedAllLabels: [String] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.services) private var services

    /// Selected colorway ID from user preferences
    @AppStorage("overlayColorwayId") private var selectedColorwayId: String = GMKColorway.default.id

    /// The active GMK colorway
    private var activeColorway: GMKColorway {
        GMKColorway.find(id: selectedColorwayId) ?? .default
    }

    /// Size of a standard 1u key in points
    private let keyUnitSize: CGFloat = 32
    /// Gap between keys
    private let keyGap: CGFloat = 2

    /// Numpad keyCodes that should be excluded from floating labels
    /// (numpad has same labels as main keyboard but shouldn't get floating labels)
    private static let numpadKeyCodes: Set<UInt16> = [
        65, 67, 69, 71, 75, 76, 78, 81, // operators and special
        82, 83, 84, 85, 86, 87, 88, 89, 91, 92 // numbers 0-9
    ]

    /// Build mapping from label → keyCode for the current keymap
    /// Used to determine which keycap a floating label should animate to
    /// Cached to avoid rebuilding on every access (accessed ~94 times per render)
    private var labelToKeyCode: [String: UInt16] {
        // Return cached value if available
        if !cachedLabelToKeyCode.isEmpty {
            return cachedLabelToKeyCode
        }

        // Build mapping (cache will be populated by rebuildLabelToKeyCodeCache)
        return rebuildLabelToKeyCodeCache()
    }

    /// Rebuild the label-to-keyCode mapping cache
    /// Called when layout/keymap changes to refresh the cache
    private func rebuildLabelToKeyCodeCache() -> [String: UInt16] {
        var result: [String: UInt16] = [:]
        for key in layout.keys {
            // Skip numpad keys - they have same labels as main keyboard
            // but shouldn't receive floating labels (they render their own)
            if Self.numpadKeyCodes.contains(key.keyCode) {
                continue
            }
            let label = keymap.displayLabel(for: key, includeExtraKeys: includeKeymapPunctuation)
            // Use uppercase for consistent matching
            result[label.uppercased()] = key.keyCode
        }
        return result
    }

    /// Base set of labels for floating label animation (A-Z, 0-9, common punctuation).
    /// The active keymap may contribute additional labels (e.g., Turkish ğ, Nordic ð).
    private static let baseLabels: Set<String> = {
        // Letters A-Z (uppercase for consistent matching)
        let letters = (65 ... 90).map { String(UnicodeScalar($0)) }
        // Numbers 0-9
        let numbers = (0 ... 9).map { String($0) }
        // Common punctuation
        let punctuation = [";", "'", ",", ".", "/", "[", "]", "\\", "`", "-", "="]
        // International characters commonly used in static keymaps
        let international = ["ö", "Ö", "ä", "Ä", "ü", "Ü", "ß", "é", "É", "è", "È", "ê", "Ê",
                             "à", "À", "ç", "Ç", "ñ", "Ñ", "å", "Å", "ø", "Ø", "æ", "Æ"]
        return Set(letters + numbers + punctuation + international)
    }()

    /// All labels for floating label animation — base pool plus any dynamic labels from the active keymap.
    /// Cached alongside labelToKeyCode to avoid recomputation on every body pass.
    private var allLabels: [String] {
        if !cachedAllLabels.isEmpty {
            return cachedAllLabels
        }
        return rebuildAllLabelsCache()
    }

    /// Rebuild the floating label pool from base labels + active keymap labels.
    private func rebuildAllLabelsCache() -> [String] {
        var labels = Self.baseLabels
        labels.formUnion(labelToKeyCode.keys)
        return labels.sorted()
    }

    // MARK: - Floating Label Visibility

    private var floatingLabelVisibility: FloatingLabelVisibility {
        let ltk = labelToKeyCode

        var remapped = Set<String>()
        if !isKeymapTransitioning {
            for (label, keyCode) in ltk {
                let inputKeyName = Self.keyCodeToKanataName(keyCode).lowercased()
                if let info = layerKeyMap[keyCode],
                   Self.shouldHideFloatingLabel(for: info, baseLabel: label, inputKeyName: inputKeyName)
                {
                    remapped.insert(label)
                }
            }
        }

        var zoneSubs = Set<String>()
        for (label, keyCode) in ltk {
            if activeZoneSubtitles[keyCode] != nil {
                zoneSubs.insert(label)
            }
        }

        // When unmapped keys render base-style, let their floating shift legends
        // (e.g. "!" over "1") show again. Mapped/remapped/zone keys are excluded
        // by remappedLabels / zoneSubtitleLabels, so only unmapped keys gain them.
        // Read via the same injected `services` the keycaps use, so both halves
        // of the feature always agree on the preference instance.
        let baseStyleUnmapped = services.preferences.unmappedLayerKeyStyle == .baseLayer
        return FloatingLabelVisibility(
            labelToKeyCode: ltk,
            isLauncherMode: isLauncherMode,
            isLayerMode: baseStyleUnmapped ? false : isLayerMode,
            vimHintsActive: vimHintsActive,
            remappedLabels: remapped,
            zoneSubtitleLabels: zoneSubs
        )
    }

    nonisolated static func shouldHideFloatingLabel(
        for info: LayerKeyInfo,
        baseLabel: String,
        inputKeyName: String
    ) -> Bool {
        if info.isTransparent {
            return false
        }
        if info.isLayerSwitch {
            return true
        }
        if info.appLaunchIdentifier != nil || info.systemActionIdentifier != nil || info.urlIdentifier != nil {
            return true
        }
        if let outputKey = info.outputKey {
            return outputKey.lowercased() != inputKeyName
        }
        return !info.displayLabel.isEmpty && info.displayLabel.uppercased() != baseLabel.uppercased()
    }

    var keyboardAccessibilityLabel: String {
        "Keyboard overlay, \(layout.name), layer \(currentLayerName)"
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = calculateScale(for: geometry.size)
            let keys = layout.keys
            let escLeftInset = OverlayKeyboardView.escLeftInset(
                for: layout,
                scale: scale,
                keyUnitSize: keyUnitSize,
                keyGap: keyGap
            )
            ZStack(alignment: .topLeading) {
                // Layer 1: Keycap backgrounds (stable positions)
                ForEach(keys, id: \.id) { key in
                    keyView(key: key, scale: scale)
                }

                // Layer 3: KindaVim hints (renders only while pack is
                // installed, frontmost app isn't ignored, and adapter
                // mode is normal / op-pending / visual). Sits on top of
                // the keycaps but below the floating-label animation.
                if vimHintsActive {
                    VimHintLayer(
                        layout: layout,
                        scale: scale,
                        keyFrame: { key in
                            CGRect(
                                x: keyPositionX(for: key, scale: scale)
                                    - keyWidth(for: key, scale: scale) / 2,
                                y: keyPositionY(for: key, scale: scale)
                                    - keyHeight(for: key, scale: scale) / 2,
                                width: keyWidth(for: key, scale: scale),
                                height: keyHeight(for: key, scale: scale)
                            )
                        }
                    )
                }

                // Layer 2: Floating labels (animate between keycap positions)
                // Labels are ALWAYS visible when in current keymap (like the working symbol animation).
                // The enableAnimation flag controls whether position changes animate.
                // Note: frames are calculated directly from layout, no GeometryReader needed.
                // Skip floating labels for non-standard legend styles (dots show circles, not letters)
                if !reduceMotion, activeColorway.legendStyle == .standard {
                    let visibility = floatingLabelVisibility
                    ForEach(allLabels, id: \.self) { label in
                        FloatingKeymapLabel(
                            label: label,
                            targetFrame: targetFrameFor(label, scale: scale),
                            isVisible: visibility.isVisible(label),
                            scale: scale,
                            colorway: activeColorway,
                            // Enable animation after initial render (prevents animation on drawer open)
                            enableAnimation: initialRenderComplete,
                            // Instant visibility for all layer transitions (no fade in or out)
                            animateVisibility: false,
                            // Pass fade amount and dark mode for glow effect
                            fadeAmount: fadeAmount,
                            isDarkMode: isDarkMode,
                            // System keymap shift label override
                            shiftSymbolOverride: floatingLabelShiftOverride(for: label)
                        )
                        // Skip re-rendering labels whose display inputs are unchanged
                        // when the parent re-renders for unrelated state (#485).
                        .equatable()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preference(key: EscKeyLeftInsetPreferenceKey.self, value: escLeftInset)
            // Disable all animations during launcher mode transitions
            .animation(nil, value: isLauncherMode)
        }
        .aspectRatio(layout.totalWidth / layout.totalHeight, contentMode: .fit)
        // Also disable at container level for any inherited animations
        .animation(nil, value: isLauncherMode)
        .onChange(of: effectivePressedKeyCodes) { _, _ in
            // Update caps lock state when any key changes (captures toggle)
            isCapsLockOn = NSEvent.modifierFlags.contains(.capsLock)
        }
        .onChange(of: isCapsLockOn) { _, newValue in
            // Kanata toggles caps lock via IOHIDSetModifierLockState which updates
            // the system state but never produces a flagsChanged CGEvent. Without
            // that event, macOS won't show the cursor badge. Post a synthetic one
            // at the session level (bypasses kanata's HID tap so it won't be swallowed).
            guard let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0x39,
                keyDown: true
            ) else { return }
            event.type = .flagsChanged
            if newValue {
                event.flags.insert(.maskAlphaShift)
            } else {
                event.flags.remove(.maskAlphaShift)
            }
            event.post(tap: .cgSessionEventTap)
        }
        .onChange(of: keymap.id) { oldValue, newValue in
            guard oldValue != newValue else { return }
            previousKeymapId = newValue
            // Rebuild labelToKeyCode cache when keymap changes
            cachedLabelToKeyCode = rebuildLabelToKeyCodeCache()
            cachedAllLabels = rebuildAllLabelsCache()

            // Activate keymap transition window to enable floating label animation
            // during keymap switches (QWERTY → Dvorak, etc.)
            isKeymapTransitioning = true
            // Deactivate after 600ms (enough time for wobble animation to complete)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                isKeymapTransitioning = false
            }
        }
        .onChange(of: includeKeymapPunctuation) { _, _ in
            // Rebuild labelToKeyCode cache when punctuation toggle changes
            cachedLabelToKeyCode = rebuildLabelToKeyCodeCache()
            cachedAllLabels = rebuildAllLabelsCache()
        }
        .onChange(of: layout.id) { _, _ in
            // Rebuild labelToKeyCode cache when layout changes
            cachedLabelToKeyCode = rebuildLabelToKeyCodeCache()
            cachedAllLabels = rebuildAllLabelsCache()
        }
        .onAppear {
            previousKeymapId = keymap.id
            // Build initial cache
            cachedLabelToKeyCode = rebuildLabelToKeyCodeCache()
            cachedAllLabels = rebuildAllLabelsCache()
            // Enable animation after initial render completes
            // This ensures the first load positions keys without animation,
            // but subsequent keymap changes animate properly (deferred to next run loop tick)
            Task { @MainActor in
                initialRenderComplete = true
            }
            // Monitor flagsChanged globally so caps lock LED updates even when
            // kanata toggles it via IOHIDSetModifierLockState (no CGEvent tap hit)
            flagsChangedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { _ in
                let capsLock = NSEvent.modifierFlags.contains(.capsLock)
                if capsLock != isCapsLockOn {
                    isCapsLockOn = capsLock
                }
            }
        }
        .onDisappear {
            if let monitor = flagsChangedMonitor {
                NSEvent.removeMonitor(monitor)
                flagsChangedMonitor = nil
            }
        }
    }

    /// Get target frame for a floating label based on current keymap
    /// Calculates frame directly from layout instead of using GeometryReader
    private func targetFrameFor(_ label: String, scale: CGFloat) -> CGRect {
        // Normalize label to uppercase for consistent lookup (allLabels contains uppercase)
        let normalizedLabel = label.uppercased()
        if let keyCode = labelToKeyCode[normalizedLabel],
           let key = layout.keys.first(where: { $0.keyCode == keyCode })
        {
            let width = keyWidth(for: key, scale: scale)
            let height = keyHeight(for: key, scale: scale)
            let centerX = keyPositionX(for: key, scale: scale)
            let centerY = keyPositionY(for: key, scale: scale)
            return CGRect(
                x: centerX - width / 2,
                y: centerY - height / 2,
                width: width,
                height: height
            )
        }
        // Park off-screen if not in current keymap
        return CGRect(x: -100, y: -100, width: 20, height: 20)
    }

    private func keyView(key: PhysicalKey, scale: CGFloat) -> some View {
        // Use TCP KeyInput for physical key detection (no CGEvent fallback)
        // TCP KeyInput shows the physical key pressed, not the remapped output
        // Requires Kanata built from keypath-v1.10.0-base branch
        let isPressed = effectivePressedKeyCodes.contains(key.keyCode)

        if key.keyCode == 57, isPressed || holdLabels[key.keyCode] != nil {
            AppLogger.shared.debug(
                "🧪 [Overlay] keyCode=57 pressed=\(isPressed) holdLabel=\(holdLabels[key.keyCode] ?? "nil") layerLabel=\(layerKeyMap[key.keyCode]?.displayLabel ?? "nil")"
            )
        }

        let baseLabel = keymap.displayLabel(
            for: key,
            includeExtraKeys: includeKeymapPunctuation
        )

        // Look up launcher mapping for this key by kanata name first (handles special keys
        // like enter/rightshift whose display labels differ from their mapping keys),
        // then fall back to display label for standard letter/number/punctuation keys
        let kanataName = OverlayKeyboardView.keyCodeToKanataName(key.keyCode).lowercased()
        let launcherMapping = launcherMappings[kanataName] ?? launcherMappings[baseLabel.lowercased()]

        // Look up per-key shift label from system keymap when active
        let shiftOverride: String? = if keymap.id == LogicalKeymap.systemId {
            systemShiftLabel(for: key.keyCode)
        } else {
            nil
        }

        let floatingLabelsEnabled = !reduceMotion && activeColorway.legendStyle == .standard
        let shouldSuppressKeycapLabel = floatingLabelsEnabled
            && floatingLabelVisibility.suppressesKeycapContent(baseLabel)

        return OverlayKeycapView(
            key: key,
            baseLabel: baseLabel,
            isPressed: isPressed,
            scale: scale,
            isDarkMode: isDarkMode,
            isCapsLockOn: isCapsLockOn,
            fadeAmount: fadeAmount,
            currentLayerName: currentLayerName,
            isLoadingLayerMap: isLoadingLayerMap,
            layerKeyInfo: layerKeyMap[key.keyCode],
            isEmphasized: emphasizedKeyCodes.contains(key.keyCode),
            isOneShot: oneShotKeyCodes.contains(key.keyCode),
            holdLabel: holdLabels[key.keyCode],
            isHoldActive: holdActiveKeyCodes.contains(key.keyCode),
            tapHoldIdleLabel: tapHoldIdleLabels[key.keyCode],
            onKeyClick: onKeyClick,
            onKeyDoubleClick: onKeyDoubleClick,
            colorway: activeColorway,
            // Pass layout width for rainbow gradient calculation
            layoutTotalWidth: layout.totalWidth,
            // Hide a keycap alpha label only when the floating/hint overlay owns
            // that label. Layer, launcher, remapped, and zone labels render inline.
            // Disable floating labels for non-standard legend styles (dots, blank, etc.)
            useFloatingLabels: shouldSuppressKeycapLabel,
            // Kinesis keyboards have scooped/dished home row keys
            showScoopedHomeRow: layout.id == "kinesis-360",
            // Selection highlight for mapper drawer
            isSelected: selectedKeyCode == key.keyCode,
            // Rule hover highlight (from Custom Rules or Launcher tabs)
            isHoveredByRule: hoveredRuleKeyCode == key.keyCode,
            // Inspector/drawer state for click vs drag behavior
            isInspectorVisible: isInspectorVisible,
            // Custom icon from push-msg
            customIcon: customIcons[key.keyCode],
            // Shift label override from system keymap
            shiftLabelOverride: shiftOverride,
            // Launcher mode state
            isLauncherMode: isLauncherMode,
            launcherMapping: launcherMapping,
            // Keymap transition flag (bypasses remap gating for animation)
            isKeymapTransitioning: isKeymapTransitioning,
            zoneColor: activeZoneColors[key.keyCode],
            zoneSubtitle: activeZoneSubtitles[key.keyCode]
        )
        .frame(
            width: keyWidth(for: key, scale: scale),
            height: keyHeight(for: key, scale: scale)
        )
        .rotationEffect(.degrees(key.rotation))
        .position(
            x: keyPositionX(for: key, scale: scale),
            y: keyPositionY(for: key, scale: scale)
        )
    }

    // MARK: - Layout Calculations

    private func calculateScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / (layout.totalWidth * (keyUnitSize + keyGap))
        let heightScale = size.height / (layout.totalHeight * (keyUnitSize + keyGap))
        return min(widthScale, heightScale)
    }

    private func keyWidth(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        (key.width * keyUnitSize + (key.width - 1) * keyGap) * scale
    }

    private func keyHeight(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        (key.height * keyUnitSize + (key.height - 1) * keyGap) * scale
    }

    private func keyPositionX(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        // Use visualX which applies rotation transform for ergonomic keyboards
        let baseX = key.visualX * (keyUnitSize + keyGap) * scale
        let halfWidth = keyWidth(for: key, scale: scale) / 2
        return baseX + halfWidth + keyGap * scale
    }

    private func keyPositionY(for key: PhysicalKey, scale: CGFloat) -> CGFloat {
        // Use visualY which applies rotation transform for ergonomic keyboards
        let baseY = key.visualY * (keyUnitSize + keyGap) * scale
        let halfHeight = keyHeight(for: key, scale: scale) / 2
        return baseY + halfHeight + keyGap * scale
    }

    nonisolated static func escLeftInset(
        for layout: PhysicalLayout,
        scale: CGFloat,
        keyUnitSize: CGFloat = 32,
        keyGap: CGFloat = 2
    ) -> CGFloat {
        guard let escKey = layout.keys.first(where: { $0.keyCode == 53 }) else {
            return keyGap * scale
        }

        let keyWidth = (escKey.width * keyUnitSize + (escKey.width - 1) * keyGap) * scale
        let baseX = escKey.x * (keyUnitSize + keyGap) * scale
        let halfWidth = keyWidth / 2
        let positionX = baseX + halfWidth + keyGap * scale
        let leftEdge = positionX - halfWidth
        return max(0, leftEdge)
    }

    // MARK: - System Keymap Shift Labels

    /// Get the shift label for a keyCode from the system keymap provider.
    /// Returns nil if the shifted character is the same as the base uppercased (e.g., a→A).
    @MainActor
    private func systemShiftLabel(for keyCode: UInt16) -> String? {
        let provider = SystemKeyLabelProvider.shared
        guard let shifted = provider.currentShiftLabels[keyCode],
              let base = provider.currentLabels[keyCode]
        else {
            return nil
        }
        // Don't show shift label if it's just the uppercase of the base (e.g., a→A)
        if shifted == base.uppercased(), base.count == 1 {
            return nil
        }
        return shifted
    }

    /// Get shift override for a floating label (by label string, not keyCode).
    @MainActor
    private func floatingLabelShiftOverride(for label: String) -> String? {
        guard keymap.id == LogicalKeymap.systemId else { return nil }
        guard let keyCode = labelToKeyCode[label.uppercased()] else { return nil }
        return systemShiftLabel(for: keyCode)
    }

    // MARK: - Key Code to Kanata Name Mapping

    /// Maps CGEvent key codes to OsCode Display names (lowercase).
    /// These match what Kanata sends via TCP KeyInput events: OsCode.to_string().to_lowercase()
    nonisolated static func keyCodeToKanataName(_ keyCode: UInt16) -> String {
        switch keyCode {
        // Row 3: Home row (ASDF...)
        case 0: "a"
        case 1: "s"
        case 2: "d"
        case 3: "f"
        case 4: "h"
        case 5: "g"
        // Row 4: Bottom row (ZXCV...)
        case 6: "z"
        case 7: "x"
        case 8: "c"
        case 9: "v"
        case 11: "b"
        // Row 2: Top row (QWERTY...)
        case 12: "q"
        case 13: "w"
        case 14: "e"
        case 15: "r"
        case 16: "y"
        case 17: "t"
        // Row 1: Number row
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "equal"
        case 25: "9"
        case 26: "7"
        case 27: "minus"
        case 28: "8"
        case 29: "0"
        // More top row keys
        case 30: "rightbrace"
        case 31: "o"
        case 32: "u"
        case 33: "leftbrace"
        case 34: "i"
        case 35: "p"
        // Home row continued
        case 36: "enter"
        case 37: "l"
        case 38: "j"
        case 39: "apostrophe"
        case 40: "k"
        case 41: "semicolon"
        case 42: "backslash"
        // Bottom row continued
        case 43: "comma"
        case 44: "slash"
        case 45: "n"
        case 46: "m"
        case 47: "dot"
        // Special keys
        case 48: "tab"
        case 49: "space"
        case 50: "grave"
        case 51: "backspace"
        case 53: "esc"
        // Modifiers
        case 54: "rightmeta"
        case 55: "leftmeta"
        case 56: "leftshift"
        case 57: "capslock"
        case 58: "leftalt"
        case 59: "leftctrl"
        case 60: "rightshift"
        case 61: "rightalt"
        case 63: "fn"
        // Function keys
        case 96: "f5"
        case 97: "f6"
        case 98: "f7"
        case 99: "f3"
        case 100: "f8"
        case 101: "f9"
        case 103: "f11"
        case 109: "f10"
        case 111: "f12"
        case 118: "f4"
        case 120: "f2"
        case 122: "f1"
        // Arrow keys
        case 123: "left"
        case 124: "right"
        case 125: "down"
        case 126: "up"
        // ISO key (between Left Shift and Z on ISO keyboards)
        case 10: "intlbackslash"
        // ABNT2 extra key (between slash and right shift on Brazilian keyboards)
        case 94: "intlro" // International Ro key (ABNT2)
        // Korean language toggle keys
        case 104: "hangeul" // Hanja key
        // Navigation keys
        case 115: "home"
        case 116: "pageup"
        case 117: "del"
        case 119: "end"
        case 121: "pagedown"
        case 114: "help"
        // Extended function keys
        case 64: "f17"
        case 79: "f18"
        case 80: "f19"
        case 102: "rightctrl" // Also used for Han/Eng toggle on Korean keyboards
        case 105: "f13"
        case 106: "f16"
        case 107: "f14"
        case 113: "f15"
        default:
            "unknown-\(keyCode)"
        }
    }
}

// MARK: - Preview

#Preview("Overlay Keyboard - Pressed Keys") {
    OverlayKeyboardView(
        layout: .macBookUS,
        keymap: .qwertyUS,
        includeKeymapPunctuation: false,
        pressedKeyCodes: [0, 56, 55] // a, leftshift, leftmeta
    )
    .padding()
    .frame(width: 600, height: 250)
    .background(Color(white: 0.1))
}

#Preview("Overlay Keyboard - Empty Dark") {
    OverlayKeyboardView(
        layout: .macBookUS,
        keymap: .colemakDH,
        includeKeymapPunctuation: true,
        pressedKeyCodes: []
    )
    .padding()
    .frame(width: 600, height: 250)
    .background(Color.black)
}
