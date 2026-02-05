import AppKit
import Carbon
import Combine
import Foundation
import KeyPathCore
import SwiftUI

extension KeyboardVisualizationViewModel {
    // MARK: - TCP Key Input Handling

    /// Set up observer for Kanata TCP KeyInput events (physical key presses)
    func setupKeyInputObserver() {
        keyInputObserver = NotificationCenter.default.addObserver(
            forName: .kanataKeyInput,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let key = notification.userInfo?["key"] as? String,
                  let actionStr = notification.userInfo?["action"] as? String
            else { return }

            Task { @MainActor in
                self.handleTcpKeyInput(key: key, action: actionStr)
            }
        }
        AppLogger.shared.debug("⌨️ [KeyboardViz] TCP key input observer registered")
    }

    /// Set up observer for Kanata TCP heartbeat events (layer polling)
    func setupTcpHeartbeatObserver() {
        tcpHeartbeatObserver = NotificationCenter.default.addObserver(
            forName: .kanataTcpHeartbeat,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.noteTcpEventReceived()
            }
        }
        AppLogger.shared.debug("⌨️ [KeyboardViz] TCP heartbeat observer registered")
    }

    /// Set up observer for Kanata TCP HoldActivated events (tap-hold transitions to hold)
    func setupHoldActivatedObserver() {
        holdActivatedObserver = NotificationCenter.default.addObserver(
            forName: .kanataHoldActivated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let key = notification.userInfo?["key"] as? String,
                  let action = notification.userInfo?["action"] as? String
            else { return }

            Task { @MainActor in
                self.handleHoldActivated(key: key, action: action)
            }
        }
        AppLogger.shared.debug("⌨️ [KeyboardViz] Hold activated observer registered")
    }

    /// Set up observer for Kanata TCP TapActivated events (tap-hold triggers tap action)
    func setupTapActivatedObserver() {
        tapActivatedObserver = NotificationCenter.default.addObserver(
            forName: .kanataTapActivated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let key = notification.userInfo?["key"] as? String,
                  let action = notification.userInfo?["action"] as? String
            else { return }

            Task { @MainActor in
                self.handleTapActivated(key: key, action: action)
            }
        }
        AppLogger.shared.debug("⌨️ [KeyboardViz] Tap activated observer registered")
    }

    /// Set up observer for Kanata TCP MessagePush events (icon/emphasis messages)
    func setupMessagePushObserver() {
        messagePushObserver = NotificationCenter.default.addObserver(
            forName: .kanataMessagePush,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let message = notification.userInfo?["message"] as? String else { return }

            Task { @MainActor in
                self.handleMessagePush(message)
            }
        }
        AppLogger.shared.debug("⌨️ [KeyboardViz] Message push observer registered")
    }

    /// Set up observer for rule collections changed notification (for real-time feature toggle updates)
    func setupRuleCollectionsObserver() {
        ruleCollectionsObserver = NotificationCenter.default.addObserver(
            forName: .ruleCollectionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.loadFeatureCollectionStates()
                // Invalidate layer mapping cache so toggled rules take effect immediately
                self.invalidateLayerMappings()
                // Re-preload icons when collections change (cache warming for new mappings)
                self.preloadAllIcons()
                AppLogger.shared.debug("⌨️ [KeyboardViz] Reloaded feature collection states, invalidated cache, and preloaded icons after change")
            }
        }
        AppLogger.shared.debug("⌨️ [KeyboardViz] Rule collections observer registered")
    }

    /// Set up observer for one-shot modifier activations
    func setupOneShotObserver() {
        oneShotObserver = NotificationCenter.default.addObserver(
            forName: .kanataOneShotActivated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let modifiers = notification.userInfo?["modifiers"] as? String else { return }

            Task { @MainActor in
                self.handleOneShotActivated(modifiers: modifiers)
            }
        }
        AppLogger.shared.debug("⌨️ [KeyboardViz] One-shot observer registered")
    }

    /// Set up subscription for app context changes (app-specific key overrides)
    func setupAppContextObserver() {
        appContextCancellable = AppContextService.shared.$currentBundleIdentifier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bundleId in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleAppContextChange(bundleId: bundleId)
                }
            }
        AppLogger.shared.debug("⌨️ [KeyboardViz] App context observer registered")
    }

    /// Handle app context change - apply app-specific key overrides to layerKeyMap
    func handleAppContextChange(bundleId: String?) async {
        // Skip if app hasn't actually changed
        guard bundleId != currentAppBundleId else { return }
        currentAppBundleId = bundleId

        AppLogger.shared.info("🔄 [KeyboardViz] App context changed: \(bundleId ?? "nil")")

        // Rebuild layer mapping to include/exclude app-specific overrides
        rebuildLayerMapping()
    }

    /// Apply app-specific overrides to the layer key map.
    /// Returns a new map with overrides applied for the current app.
    func applyAppSpecificOverrides(to baseMap: [UInt16: LayerKeyInfo]) async -> [UInt16: LayerKeyInfo] {
        guard let bundleId = currentAppBundleId else { return baseMap }

        // Load app keymaps
        let keymaps = await AppKeymapStore.shared.loadKeymaps()

        // Find the keymap for the current app
        guard let appKeymap = keymaps.first(where: {
            $0.mapping.bundleIdentifier == bundleId && $0.mapping.isEnabled
        }) else {
            return baseMap
        }

        // Apply overrides
        var modifiedMap = baseMap
        for override in appKeymap.overrides {
            // Find the keyCode for this input key
            guard let keyCode = Self.kanataNameToKeyCode(override.inputKey) else {
                AppLogger.shared.debug("⚠️ [KeyboardViz] Unknown key for override: \(override.inputKey)")
                continue
            }

            // Create a new LayerKeyInfo with the override output
            let displayLabel = formatOutputForDisplay(override.outputAction)
            let newInfo = LayerKeyInfo.mapped(
                displayLabel: displayLabel,
                outputKey: override.outputAction,
                outputKeyCode: Self.kanataNameToKeyCode(override.outputAction)
            )

            modifiedMap[keyCode] = newInfo
            AppLogger.shared.info("🔄 [KeyboardViz] Applied app override: \(override.inputKey) → \(override.outputAction) (keyCode \(keyCode))")
        }

        return modifiedMap
    }

    /// Format an output action for display on the keycap
    func formatOutputForDisplay(_ output: String) -> String {
        // Simple case: single key name
        let trimmed = output.trimmingCharacters(in: .whitespaces)

        // If it's a single letter, uppercase it
        if trimmed.count == 1 {
            return trimmed.uppercased()
        }

        // For complex actions, show abbreviated form
        if trimmed.hasPrefix("(") {
            // Extract action type for common macros
            if trimmed.contains("macro") { return "⌘M" }
            if trimmed.contains("tap-hold") { return "⇥" }
            return "..."
        }

        // For known key names, uppercase them
        return trimmed.uppercased()
    }

    /// Handle one-shot modifier activation
    /// Adds modifier to active set - will be cleared on next key press
    func handleOneShotActivated(modifiers: String) {
        noteTcpEventReceived()
        // Parse comma-separated modifiers (e.g., "lsft" or "lsft,lctl")
        let mods = modifiers.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        for mod in mods {
            activeOneShotModifiers.insert(mod)
        }
        AppLogger.shared.info("⚡ [KeyboardViz] One-shot activated: \(modifiers) → active: \(activeOneShotModifiers)")
    }

    /// Clear one-shot modifiers (called after next key press)
    func clearOneShotModifiers() {
        guard !activeOneShotModifiers.isEmpty else { return }
        AppLogger.shared.info("⚡ [KeyboardViz] Clearing one-shot modifiers: \(activeOneShotModifiers)")
        activeOneShotModifiers.removeAll()
    }

    /// Handle a MessagePush event from Kanata (icon/emphasis commands)
    /// Format: "icon:arrow-left", "emphasis:h,j,k,l", "emphasis:clear"
    func handleMessagePush(_ message: String) {
        noteTcpEventReceived()
        // Parse icon messages: "icon:arrow-left"
        if message.hasPrefix("icon:") {
            let iconName = String(message.dropFirst(5)) // Remove "icon:" prefix

            // Associate icon with most recently pressed key
            guard let keyCode = lastPressedKeyCode else {
                AppLogger.shared.debug("🎨 [KeyboardViz] Icon message '\(iconName)' received but no key was pressed recently")
                return
            }

            AppLogger.shared.info("🎨 [KeyboardViz] Associating icon '\(iconName)' with key \(keyCode)")

            // Cancel any existing clear task for this key
            iconClearTasks[keyCode]?.cancel()

            // Set the icon
            customIcons[keyCode] = iconName

            // Clear the icon after 2 seconds
            iconClearTasks[keyCode] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.customIcons.removeValue(forKey: keyCode)
                self?.iconClearTasks.removeValue(forKey: keyCode)
                AppLogger.shared.debug("🎨 [KeyboardViz] Cleared icon for key \(keyCode)")
            }

            return
        }

        // Parse emphasis messages: "emphasis:h,j,k,l" or "emphasis:clear"
        if message.hasPrefix("emphasis:") {
            let value = String(message.dropFirst(9)) // Remove "emphasis:" prefix

            if value == "clear" {
                customEmphasisKeyCodes.removeAll()
                AppLogger.shared.info("✨ [KeyboardViz] Emphasis cleared")
                return
            }

            // Parse comma or space-separated key names
            let keyNames = value.split(whereSeparator: { $0 == "," || $0.isWhitespace })
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

            var keyCodes: Set<UInt16> = []
            for keyName in keyNames {
                if let keyCode = Self.kanataNameToKeyCode(keyName) {
                    keyCodes.insert(keyCode)
                } else {
                    AppLogger.shared.warn("⚠️ [KeyboardViz] Unknown key name in emphasis: \(keyName)")
                }
            }

            customEmphasisKeyCodes = keyCodes
            AppLogger.shared.info("✨ [KeyboardViz] Emphasis set: \(keyNames.joined(separator: ", ")) -> \(keyCodes)")
            return
        }

        // Parse layer messages: "layer:nav", "layer:base"
        // These come from push-msg fake keys used by momentary layer activators
        if message.hasPrefix("layer:") {
            let layerName = String(message.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            AppLogger.shared.info("🗂️ [KeyboardViz] Layer push message: '\(layerName)'")
            // Update the layer and rebuild mappings
            updateLayer(layerName)
            return
        }

        AppLogger.shared.debug("📨 [KeyboardViz] Unhandled push message: \(message)")
    }

    /// Handle a HoldActivated event from Kanata
    func handleHoldActivated(key: String, action: String) {
        noteTcpEventReceived()
        guard let keyCode = Self.kanataNameToKeyCode(key) else {
            AppLogger.shared.debug("⌨️ [KeyboardViz] Unknown kanata key name for hold: \(key)")
            return
        }

        // Convert the action string to a display label; if empty, wait for simulator resolution.
        if !action.isEmpty {
            let displayLabel = Self.actionToDisplayLabel(action)
            holdLabels[keyCode] = displayLabel
        }
        holdActiveKeyCodes.insert(keyCode)
        AppLogger.shared.info("🔒 [KeyboardViz] Hold activated: \(key) -> '\(holdLabels[keyCode] ?? "pending")' (from '\(action)')")

        // If Kanata omitted the action string, try to resolve the hold label via simulator
        if action.isEmpty {
            guard FeatureFlags.simulatorAndVirtualKeysEnabled else {
                AppLogger.shared.debug("🔒 [KeyboardViz] Simulator disabled; skipping hold label resolution for \(key)")
                return
            }
            // Check short-lived cache first
            if let cached = holdLabelCache[keyCode], Date().timeIntervalSince(cached.timestamp) < holdLabelCacheTTL {
                holdLabels[keyCode] = cached.label
                AppLogger.shared.debug("🔒 [KeyboardViz] Hold label served from cache: \(key) -> '\(cached.label)'")
                return
            }

            let configPath = WizardSystemPaths.userConfigPath
            let layer = currentLayerName
            // Avoid duplicate lookups for the same keyCode
            if resolvingHoldLabels.contains(keyCode) {
                AppLogger.shared.debug("🔒 [KeyboardViz] Hold label resolution already in-flight for \(key)")
                return
            }
            resolvingHoldLabels.insert(keyCode)

            Task.detached { [weak self] in
                guard let self else { return }
                do {
                    if let resolved = try await layerKeyMapper.holdDisplayLabel(
                        for: keyCode,
                        configPath: configPath,
                        startLayer: layer
                    ) {
                        await MainActor.run {
                            self.holdLabels[keyCode] = resolved
                            self.holdLabelCache[keyCode] = (resolved, Date())
                            AppLogger.shared.info("🔒 [KeyboardViz] Hold label resolved via simulator: \(key) -> '\(resolved)'")
                            self.resolvingHoldLabels.remove(keyCode)
                        }
                    }
                } catch {
                    await MainActor.run {
                        AppLogger.shared.debug("🔒 [KeyboardViz] Hold label resolution failed: \(error)")
                        self.resolvingHoldLabels.remove(keyCode)
                    }
                }
            }
        }
    }

    /// Handle a TapActivated event from Kanata
    /// Populates the dynamic tap-hold output map for suppression
    func handleTapActivated(key: String, action: String) {
        noteTcpEventReceived()
        guard let sourceKeyCode = Self.kanataNameToKeyCode(key) else {
            AppLogger.shared.debug("👆 [KeyboardViz] Unknown kanata key name for tap: \(key)")
            return
        }

        // The action string contains the tap output key (e.g., "esc" for caps→esc)
        // We need to map the source key to its output for suppression
        if !action.isEmpty {
            if let outputKeyCode = Self.kanataNameToKeyCode(action) {
                // Add to dynamic map for future suppression while source is held
                if dynamicTapHoldOutputMap[sourceKeyCode] == nil {
                    dynamicTapHoldOutputMap[sourceKeyCode] = []
                }
                dynamicTapHoldOutputMap[sourceKeyCode]?.insert(outputKeyCode)

                // Temporarily suppress this output key - TapActivated fires AFTER the source
                // key is released, so we suppress the output for a brief window.
                recentTapOutputs.insert(outputKeyCode)

                // Clear suppression after brief delay
                tapOutputClearTasks[outputKeyCode]?.cancel()
                tapOutputClearTasks[outputKeyCode] = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    self?.recentTapOutputs.remove(outputKeyCode)
                    self?.tapOutputClearTasks.removeValue(forKey: outputKeyCode)
                }

                AppLogger.shared.debug("👆 [KeyboardViz] Tap activated: \(key) -> \(action)")
            } else {
                AppLogger.shared.debug("👆 [KeyboardViz] Unknown output key name: \(action)")
            }
        } else {
            AppLogger.shared.debug("👆 [KeyboardViz] Tap activated with empty action: \(key)")
        }
    }

    /// Convert a Kanata action string to a display label
    /// e.g., "lctl+lmet+lalt+lsft" → "✦" (Hyper)
    nonisolated static func actionToDisplayLabel(_ action: String) -> String {
        // Check for known patterns
        let normalized = action.lowercased()

        // Hyper key (all four modifiers): ✦
        let hyperParts = Set(["lctl", "lmet", "lalt", "lsft"])
        let actionParts = Set(normalized.split(separator: "+").map(String.init))
        if actionParts == hyperParts || actionParts == Set(["lctl", "lmet", "lalt", "lshift"]) {
            return "✦"
        }

        // Meh key (Ctrl+Shift+Alt without Cmd): ◆
        let mehParts = Set(["lctl", "lalt", "lsft"])
        if actionParts == mehParts {
            return "◆"
        }

        // Single modifiers
        if normalized == "lctl" || normalized == "rctl" || normalized == "ctrl" {
            return "⌃"
        }
        if normalized == "lmet" || normalized == "rmet" || normalized == "cmd" {
            return "⌘"
        }
        if normalized == "lalt" || normalized == "ralt" || normalized == "alt" || normalized == "opt" {
            return "⌥"
        }
        if normalized == "lsft" || normalized == "rsft" || normalized == "shift" {
            return "⇧"
        }

        // Layer switches
        if normalized.hasPrefix("layer-while-held ") || normalized.hasPrefix("layer-toggle ") {
            let layerName = String(normalized.dropFirst(normalized.hasPrefix("layer-while-held ") ? 17 : 13))
            return "[\(layerName)]"
        }

        // Fallback: show first 3 chars of action
        if action.count > 3 {
            return String(action.prefix(3)) + "…"
        }
        return action.isEmpty ? "⬤" : action
    }

    /// Handle a TCP KeyInput event from Kanata
    func handleTcpKeyInput(key: String, action: String) {
        guard let keyCode = Self.kanataNameToKeyCode(key) else {
            AppLogger.shared.debug("⌨️ [KeyboardViz] Unknown kanata key name: \(key)")
            return
        }

        noteInteraction()
        noteTcpEventReceived()

        // Clear one-shot modifiers on key press (not on release)
        // One-shot modifiers apply to the next key press and are consumed
        if action == "press", !activeOneShotModifiers.isEmpty {
            // Don't clear if this is the one-shot key itself being pressed
            // (one-shot activates on press, we want to clear on the NEXT key)
            let isOneShotKey = Self.oneShotModifierKeyCodes.values.contains(keyCode)
            if !isOneShotKey {
                clearOneShotModifiers()
            }
        }

        // Check if this key is a tap-hold source key (e.g., capslock)
        // Use both dynamic map (from TapActivated events) and static fallback
        let isTapHoldSource = dynamicTapHoldOutputMap[keyCode] != nil
            || Self.fallbackTapHoldOutputMap[keyCode] != nil

        // Check if this key should be suppressed (output of active tap-hold source or simple remap)
        let shouldSuppress = shouldSuppressKeyHighlight(keyCode, source: "tcp")
        let isRemapSuppressed = FeatureFlags.keyboardSuppressionDebugEnabled
            ? suppressedRemapOutputKeyCodes.contains(keyCode)
            : false

        if FeatureFlags.keyboardSuppressionDebugEnabled,
           let mappedOutput = remapOutputMap.first(where: { $0.value == keyCode })
        {
            AppLogger.shared.debug(
                """
                🔄 [KeyboardViz] KeyInput \(key)(\(keyCode)): isRemapOutput=true, \
                sourceKey=\(mappedOutput.key), tcpPressed=\(pressedKeyCodes), \
                remapSources=\(activeRemapSourceKeyCodes), \
                suppressedRemapOutputs=\(suppressedRemapOutputKeyCodes), \
                isRemapSuppressed=\(isRemapSuppressed)
                """
            )
        }

        switch action {
        case "press", "repeat":
            // Track tap-hold source keys
            if isTapHoldSource {
                activeTapHoldSources.insert(keyCode)
                AppLogger.shared.debug("⌨️ [KeyboardViz] Tap-hold source activated: \(key) (\(keyCode))")
            }

            if remapOutputMap[keyCode] != nil {
                recentRemapSourceKeyCodes.remove(keyCode)
                remapSourceClearTasks[keyCode]?.cancel()
                remapSourceClearTasks.removeValue(forKey: keyCode)
            }

            // Suppress output keys of active tap-hold sources (e.g., don't light up ESC when caps is pressed)
            if shouldSuppress {
                return
            }
            cancelKeyFadeOut(keyCode) // Cancel any ongoing fade-out
            pressedKeyCodes.insert(keyCode)
            // Track most recently pressed key for icon association
            lastPressedKeyCode = keyCode
            // If a hold is already active for this key, keep it active and cancel any pending clear.
            if holdActiveKeyCodes.contains(keyCode) {
                holdClearWorkItems[keyCode]?.cancel()
                holdClearWorkItems.removeValue(forKey: keyCode)
            } else {
                // Cancel any pending delayed clear for this key
                if let work = holdClearWorkItems.removeValue(forKey: keyCode) {
                    work.cancel()
                }
            }
        case "release":
            // Keep tap-hold source active briefly after release to catch the output keystroke.
            // The output (e.g., esc from caps tap) arrives AFTER the source key is released,
            // so we delay removing from activeTapHoldSources to ensure suppression works.
            if isTapHoldSource {
                let keyCodeToRemove = keyCode
                if TestEnvironment.isRunningTests {
                    activeTapHoldSources.remove(keyCodeToRemove)
                } else {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(200))
                        self?.activeTapHoldSources.remove(keyCodeToRemove)
                    }
                }
            }

            if remapOutputMap[keyCode] != nil {
                let keyCodeToSuppress = keyCode
                recentRemapSourceKeyCodes.insert(keyCodeToSuppress)
                remapSourceClearTasks[keyCodeToSuppress]?.cancel()
                remapSourceClearTasks[keyCodeToSuppress] = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    self?.recentRemapSourceKeyCodes.remove(keyCodeToSuppress)
                    self?.remapSourceClearTasks.removeValue(forKey: keyCodeToSuppress)
                }
            }

            // If this was a suppressed key, just ignore the release too
            // But still clear any lingering hold state to prevent visual artifacts
            if shouldSuppress {
                holdActiveKeyCodes.remove(keyCode)
                holdLabels.removeValue(forKey: keyCode)
                holdLabelCache.removeValue(forKey: keyCode)
                holdClearWorkItems[keyCode]?.cancel()
                holdClearWorkItems.removeValue(forKey: keyCode)
                AppLogger.shared.debug("⌨️ [KeyboardViz] Suppressing output key release: \(key) (\(keyCode)), cleared hold state")
                return
            }

            pressedKeyCodes.remove(keyCode)
            startKeyFadeOut(keyCode) // Start fade-out animation
            // Defer clearing hold state briefly to tolerate tap-hold-press sequences that emit rapid releases.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                holdActiveKeyCodes.remove(keyCode)
                if holdLabels[keyCode] != nil {
                    holdLabels.removeValue(forKey: keyCode)
                    holdLabelCache.removeValue(forKey: keyCode)
                    AppLogger.shared.debug("⌨️ [KeyboardViz] Cleared hold label (delayed) for \(key)")
                }
                holdClearWorkItems.removeValue(forKey: keyCode)
            }
            holdClearWorkItems[keyCode]?.cancel()
            holdClearWorkItems[keyCode] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + OverlayTiming.holdReleaseGrace, execute: work)
            AppLogger.shared.debug("⌨️ [KeyboardViz] TCP KeyRelease: \(key) -> keyCode \(keyCode)")
        default:
            break
        }

        if keyCode == 57 {
            AppLogger.shared.debug(
                "🧪 [KeyboardViz] caps state: tcpPressed=\(pressedKeyCodes.contains(57)) holdActive=\(holdActiveKeyCodes.contains(57)) holdLabel=\(holdLabels[57] ?? "nil")"
            )
        }
    }

}
