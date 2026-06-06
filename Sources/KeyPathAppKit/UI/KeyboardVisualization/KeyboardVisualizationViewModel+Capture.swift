import Foundation
import KeyPathCore

@MainActor
extension KeyboardVisualizationViewModel {
    func startCapturing() {
        guard !isCapturing else {
            AppLogger.shared.debug("⌨️ [KeyboardViz] Already capturing, ignoring start request")
            return
        }

        // Skip in test environment
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug("🧪 [KeyboardViz] Test environment - skipping TCP observers")
            return
        }

        isCapturing = true

        // TCP-based key detection (no CGEvent tap needed)
        setupKeyInputObserver() // Listen for TCP-based physical key events
        setupTcpHeartbeatObserver() // Listen for layer polling heartbeat
        setupHoldActivatedObserver() // Listen for tap-hold state transitions
        setupTapActivatedObserver() // Listen for tap-hold tap triggers
        setupMessagePushObserver() // Listen for icon/emphasis push messages
        setupRuleCollectionsObserver() // Listen for collection toggle changes
        setupOneShotObserver() // Listen for one-shot modifier activations
        setupAppContextObserver() // Listen for app changes (app-specific key overrides)
        startIdleMonitor()
        rebuildLayerMapping() // Build initial layer mapping
        loadFeatureCollectionStates() // Load optional feature collection states
        preloadAllIcons() // Pre-cache launcher and layer icons
        prebuildLayerMappingsInBackground() // Warm cache for all layers
        prewarmLauncherMappings() // Pre-cache launcher mappings + icons for instant layer switch

        AppLogger.shared.info("✅ [KeyboardViz] TCP-based key capture started")
    }

    func stopCapturing() {
        guard isCapturing else { return }

        isCapturing = false

        // Clear all visual state
        keyVisualStates.removeAll()
        holdLabelCache.removeAll()
        resolvingHoldLabels.removeAll()
        customIcons.removeAll()
        customEmphasisKeyCodes.removeAll()
        activeOneShotModifiers.removeAll()

        // Clear suppression state
        activeTapHoldSources.removeAll()
        dynamicTapHoldOutputMap.removeAll()
        recentTapOutputs.removeAll()
        tapOutputClearTasks.values.forEach { $0.cancel() }
        tapOutputClearTasks.removeAll()
        recentRemapSourceKeyCodes.removeAll()
        remapSourceClearTasks.values.forEach { $0.cancel() }
        remapSourceClearTasks.removeAll()

        // Cancel all pending work items and tasks
        holdClearWorkItems.values.forEach { $0.cancel() }
        holdClearWorkItems.removeAll()
        iconClearTasks.values.forEach { $0.cancel() }
        iconClearTasks.removeAll()
        layerMapTask?.cancel()
        layerMapTask = nil
        layerPreviewTask?.cancel()
        layerPreviewTask = nil
        appContextObservationTask?.cancel()
        appContextObservationTask = nil
        isShowingLayerPreview = false

        // Remove notification observers
        for observer in [keyInputObserver, tcpHeartbeatObserver, holdActivatedObserver,
                         tapActivatedObserver, messagePushObserver, ruleCollectionsObserver,
                         oneShotObserver]
        {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
        keyInputObserver = nil
        tcpHeartbeatObserver = nil
        holdActivatedObserver = nil
        tapActivatedObserver = nil
        messagePushObserver = nil
        ruleCollectionsObserver = nil
        oneShotObserver = nil

        idleMonitorTask?.cancel()
        idleMonitorTask = nil

        AppLogger.shared.debug("⌨️ [KeyboardViz] Stopped capturing")
    }

    func isPressed(_ key: PhysicalKey) -> Bool {
        keyVisualStates[key.keyCode]?.isPressed ?? false
    }
}
