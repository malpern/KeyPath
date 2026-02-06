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

        AppLogger.shared.info("✅ [KeyboardViz] TCP-based key capture started")
    }

    func stopCapturing() {
        guard isCapturing else { return }

        isCapturing = false
        pressedKeyCodes.removeAll()
        holdLabels.removeAll()
        holdLabelCache.removeAll()
        activeTapHoldSources.removeAll()
        dynamicTapHoldOutputMap.removeAll()
        recentTapOutputs.removeAll()
        tapOutputClearTasks.values.forEach { $0.cancel() }
        tapOutputClearTasks.removeAll()
        recentRemapSourceKeyCodes.removeAll()
        remapSourceClearTasks.values.forEach { $0.cancel() }
        remapSourceClearTasks.removeAll()

        if let observer = keyInputObserver {
            NotificationCenter.default.removeObserver(observer)
            keyInputObserver = nil
        }

        if let observer = tcpHeartbeatObserver {
            NotificationCenter.default.removeObserver(observer)
            tcpHeartbeatObserver = nil
        }

        if let observer = holdActivatedObserver {
            NotificationCenter.default.removeObserver(observer)
            holdActivatedObserver = nil
        }

        if let observer = tapActivatedObserver {
            NotificationCenter.default.removeObserver(observer)
            tapActivatedObserver = nil
        }

        if let observer = messagePushObserver {
            NotificationCenter.default.removeObserver(observer)
            messagePushObserver = nil
        }

        if let observer = ruleCollectionsObserver {
            NotificationCenter.default.removeObserver(observer)
            ruleCollectionsObserver = nil
        }

        idleMonitorTask?.cancel()
        idleMonitorTask = nil

        AppLogger.shared.debug("⌨️ [KeyboardViz] Stopped capturing")
    }

    func isPressed(_ key: PhysicalKey) -> Bool {
        pressedKeyCodes.contains(key.keyCode)
    }
}
