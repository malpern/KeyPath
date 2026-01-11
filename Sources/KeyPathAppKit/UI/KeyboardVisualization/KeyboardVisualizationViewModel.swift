import AppKit
import Carbon
import Combine
import Foundation
import KeyPathCore
import SwiftUI

/// ViewModel for keyboard visualization that tracks pressed keys
@MainActor
class KeyboardVisualizationViewModel: ObservableObject {
    /// Key codes currently pressed (from Kanata TCP KeyInput events)
    @Published var pressedKeyCodes: Set<UInt16> = []
    @Published var layout: PhysicalLayout = .macBookUS
    /// Fade level for outline state (0 = fully visible, 1 = outline-only faded)
    @Published var fadeAmount: CGFloat = 0
    /// Deep fade level for full keyboard opacity (0 = normal, 1 = 5% visible)
    @Published var deepFadeAmount: CGFloat = 0
    /// Per-key fade amounts for release animation (keyCode -> fade amount 0-1)
    @Published var keyFadeAmounts: [UInt16: CGFloat] = [:]
    /// Active fade-out timers for released keys
    private var fadeOutTasks: [UInt16: Task<Void, Never>] = [:]

    // MARK: - Timing Tunables

    enum OverlayTiming {
        /// Grace period to wait for a quick re-press before clearing hold state (seconds).
        /// Trade-off: higher = less flicker, lower = less linger.
        static var holdReleaseGrace: TimeInterval {
            TestEnvironment.isRunningTests ? 0 : 0.06
        }

        /// Duration of fade-out animation when key is released (seconds).
        /// Short enough to feel snappy, long enough to create a pleasant linger effect.
        static var keyReleaseFadeDuration: TimeInterval {
            TestEnvironment.isRunningTests ? 0 : 0.25
        }
    }

    // MARK: - Layer State

    /// Current Kanata layer name (e.g., "base", "nav", "symbols")
    @Published var currentLayerName: String = "base"
    /// Whether the layer key mapping is being built (for loading indicator)
    @Published var isLoadingLayerMap: Bool = false
    /// Key code of the currently selected key in the mapper drawer (nil when no selection)
    /// Used to show a visual highlight on the key being edited
    @Published var selectedKeyCode: UInt16?
    /// Key code being hovered in rules/launcher tabs (for secondary highlight)
    @Published var hoveredRuleKeyCode: UInt16?
    /// Key mapping for the current layer: keyCode -> LayerKeyInfo
    @Published var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
    /// Hold labels for tap-hold keys that have transitioned to hold state
    /// Maps keyCode -> hold display label (e.g., "✦" for Hyper)
    @Published var holdLabels: [UInt16: String] = [:]
    /// Idle labels for tap-hold inputs (show tap output when not pressed)
    @Published var tapHoldIdleLabels: [UInt16: String] = [:]
    /// Keys currently in a hold-active state (set when HoldActivated fires).
    /// Used to keep the key visually pressed even if tap-hold implementations
    /// emit spurious release/press events while held.
    private var holdActiveKeyCodes: Set<UInt16> = []
    /// Custom icons for keys set via push-msg (keyCode -> icon name)
    /// Example: "arrow-left", "safari", "home"
    @Published var customIcons: [UInt16: String] = [:]
    /// Most recently pressed key (for icon association)
    private var lastPressedKeyCode: UInt16?
    /// Icon clear tasks (keyCode -> task that clears the icon)
    private var iconClearTasks: [UInt16: Task<Void, Never>] = [:]
    /// Keys emphasized via push-msg emphasis command
    /// Example: (push-msg "emphasis:h,j,k,l") sets HJKL as emphasized
    @Published var customEmphasisKeyCodes: Set<UInt16> = []

    // MARK: - Launcher Mode State

    /// Layer name that triggers launcher mode display
    private static let launcherLayerName = "launcher"

    /// Launcher mappings for overlay display (key -> LauncherMapping)
    /// Loaded when entering launcher layer
    @Published var launcherMappings: [String: LauncherMapping] = [:]

    /// Whether the overlay is in launcher mode (should show app icons on keys)
    var isLauncherModeActive: Bool {
        currentLayerName.lowercased() == Self.launcherLayerName
    }

    // MARK: - Optional Feature Collections

    /// Whether the Typing Sounds collection is enabled
    @Published var isTypingSoundsEnabled: Bool = false

    /// Whether the Keycap Colorway collection is enabled
    @Published var isKeycapColorwayEnabled: Bool = false

    // MARK: - TCP Connection State

    /// Whether Kanata TCP server is responding (based on receiving events)
    /// When false, overlay shows "not connected" indicator
    @Published var isKanataConnected: Bool = false

    /// Last time we received any TCP event (for connection timeout detection)
    private var lastTcpEventTime: Date?

    /// How long without events before we consider disconnected (seconds)
    private let tcpConnectionTimeout: TimeInterval = 3.0

    // MARK: - One-Shot Modifier State

    /// Active one-shot modifiers (modifier key names like "lsft", "lctl")
    /// Cleared on next key press after activation
    @Published var activeOneShotModifiers: Set<String> = []

    /// One-shot modifier key codes for visual highlighting
    /// Maps modifier name to keyCode (e.g., "lsft" -> 56)
    private static let oneShotModifierKeyCodes: [String: UInt16] = [
        "lsft": 56, "rsft": 60,
        "lctl": 59, "rctl": 62,
        "lalt": 58, "ralt": 61,
        "lmet": 55, "rmet": 54,
        "lcmd": 55, "rcmd": 54,
        "lopt": 58, "ropt": 61
    ]

    /// Get key codes for currently active one-shot modifiers
    var oneShotHighlightedKeyCodes: Set<UInt16> {
        var codes = Set<UInt16>()
        for modifier in activeOneShotModifiers {
            if let code = Self.oneShotModifierKeyCodes[modifier.lowercased()] {
                codes.insert(code)
            }
        }
        return codes
    }

    /// Tracks keys currently undergoing async hold-label resolution to avoid duplicate simulator runs
    private var resolvingHoldLabels: Set<UInt16> = []
    /// Short-lived cache of resolved hold labels to avoid repeated simulator runs (keyCode -> (label, timestamp))
    private var holdLabelCache: [UInt16: (label: String, timestamp: Date)] = [:]
    /// Cache time-to-live in seconds
    private let holdLabelCacheTTL: TimeInterval = 5
    /// Pending delayed clears for hold-active keys to tolerate tap-hold-press jitter
    private var holdClearWorkItems: [UInt16: DispatchWorkItem] = [:]

    // MARK: - Tap-Hold Output Suppression

    /// Dynamically tracks tap-hold source keys to their tap output keys.
    /// Populated when TapActivated events are received from Kanata.
    /// Example: capslock (57) -> esc (53) when TapActivated says key=caps, action=esc
    private var dynamicTapHoldOutputMap: [UInt16: Set<UInt16>] = [:]

    /// Output keyCodes that should be temporarily suppressed due to recent tap activation.
    /// Populated when TapActivated fires (since the source key may already be released).
    /// Auto-cleared after a brief delay.
    private var recentTapOutputs: Set<UInt16> = []

    /// Pending tasks to clear tap outputs from temporary suppression
    private var tapOutputClearTasks: [UInt16: Task<Void, Never>] = [:]

    /// Fallback static map for common tap-hold patterns (used when TapActivated not available).
    /// Will be phased out once TapActivated is fully deployed.
    private static let fallbackTapHoldOutputMap: [UInt16: Set<UInt16>] = [
        57: [53] // capslock -> esc (common tap-hold: caps = tap:esc, hold:hyper)
    ]

    /// Source keys that are currently pressed (for output suppression).
    /// While a source key is in this set, its mapped output keys won't be added to pressedKeyCodes.
    private var activeTapHoldSources: Set<UInt16> = []

    /// All output keyCodes that should be suppressed (computed from active sources)
    private var suppressedOutputKeyCodes: Set<UInt16> {
        activeTapHoldSources.reduce(into: Set<UInt16>()) { result, source in
            // Try dynamic map first (from TapActivated events)
            if let outputs = dynamicTapHoldOutputMap[source] {
                result.formUnion(outputs)
            }
            // Fall back to static map
            if let outputs = Self.fallbackTapHoldOutputMap[source] {
                result.formUnion(outputs)
            }
        }
    }

    // MARK: - Remap Output Suppression

    /// Maps input keyCode -> output keyCode for simple remaps.
    /// Built from layerKeyMap when mappings change.
    /// Example: A->B mapping would have [0: 11] (keyCode 0=A maps to keyCode 11=B)
    private var remapOutputMap: [UInt16: UInt16] = [:]

    /// Output keyCodes to suppress from currently-pressed remapped keys.
    /// When A->B is mapped and A is pressed, B should not light up separately.
    private var suppressedRemapOutputKeyCodes: Set<UInt16> {
        activeRemapSourceKeyCodes.reduce(into: Set<UInt16>()) { result, inputKeyCode in
            if let outputKeyCode = remapOutputMap[inputKeyCode] {
                result.insert(outputKeyCode)
            }
        }
    }

    /// Recently released remap source keys kept briefly to suppress delayed outputs.
    private var recentRemapSourceKeyCodes: Set<UInt16> = []
    /// Pending tasks to clear remap sources from temporary suppression.
    private var remapSourceClearTasks: [UInt16: Task<Void, Never>] = [:]

    /// Remap sources that should participate in suppression (pressed + recent releases).
    private var activeRemapSourceKeyCodes: Set<UInt16> {
        pressedKeyCodes.union(recentRemapSourceKeyCodes)
    }

    private func shouldSuppressKeyHighlight(_ keyCode: UInt16, source: String = "unknown") -> Bool {
        let tapHoldSuppressed = suppressedOutputKeyCodes.contains(keyCode)
        let remapSuppressed = suppressedRemapOutputKeyCodes.contains(keyCode)
        let recentTapSuppressed = recentTapOutputs.contains(keyCode)
        let shouldSuppress = tapHoldSuppressed || remapSuppressed || recentTapSuppressed

        if FeatureFlags.keyboardSuppressionDebugEnabled, shouldSuppress {
            AppLogger.shared.debug(
                "🧯 [KeyboardViz] Suppressed keyCode=\(keyCode) source=\(source) tapHold=\(tapHoldSuppressed) remap=\(remapSuppressed) recentTap=\(recentTapSuppressed) remapSources=\(activeRemapSourceKeyCodes)"
            )
        }

        return shouldSuppress
    }

    /// Key input notification observer
    private var keyInputObserver: Any?
    /// TCP heartbeat notification observer (layer polling)
    private var tcpHeartbeatObserver: Any?
    /// Hold activated notification observer
    private var holdActivatedObserver: Any?
    /// Tap activated notification observer
    private var tapActivatedObserver: Any?
    /// Push message notification observer (for icon/emphasis messages)
    private var messagePushObserver: Any?
    /// Rule collections changed notification observer (for feature toggle updates)
    private var ruleCollectionsObserver: Any?
    /// One-shot activated notification observer
    private var oneShotObserver: Any?
    /// App context change subscription (for app-specific key overrides)
    private var appContextCancellable: AnyCancellable?
    /// Current app's bundle identifier for overlay updates
    private var currentAppBundleId: String?

    // MARK: - Key Emphasis

    /// HJKL key codes for nav layer auto-emphasis (computed once from key names)
    private static let hjklKeyCodes: Set<UInt16> = ["h", "j", "k", "l"].compactMap { kanataNameToKeyCode($0) }.reduce(into: Set<UInt16>()) { $0.insert($1) }

    /// Key codes to emphasize based on current layer and custom emphasis commands
    /// HJKL keys are auto-emphasized when on nav layer, plus any custom emphasis via push-msg
    var emphasizedKeyCodes: Set<UInt16> {
        // Auto-emphasis: HJKL on nav layer
        let autoEmphasis = currentLayerName.lowercased() == "nav" ? Self.hjklKeyCodes : []

        // Merge with custom emphasis from push-msg
        return autoEmphasis.union(customEmphasisKeyCodes)
    }

    /// Effective key codes that should appear pressed (TCP physical keys only)
    /// Uses only Kanata TCP KeyInput events to show the actual physical keys pressed,
    /// not the transformed output keys from CGEvent tap.
    var effectivePressedKeyCodes: Set<UInt16> {
        // Use TCP physical keys and any keys currently in an active hold state.
        pressedKeyCodes.union(holdActiveKeyCodes)
    }

    /// Service for building layer key mappings
    private let layerKeyMapper = LayerKeyMapper()
    /// Task for building layer mapping
    private var layerMapTask: Task<Void, Never>?

    private var isCapturing = false
    private var idleMonitorTask: Task<Void, Never>?
    private var lastInteraction: Date = .init()

    private let idleTimeout: TimeInterval = 10
    private let deepFadeTimeout: TimeInterval = 48
    private let deepFadeRamp: TimeInterval = 2
    private let idlePollInterval: TimeInterval = 0.25

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

    /// Load enabled states for optional feature collections (Typing Sounds, Keycap Colorway)
    func loadFeatureCollectionStates() {
        Task { @MainActor in
            let collections = await RuleCollectionStore.shared.loadCollections()
            isTypingSoundsEnabled = collections.first { $0.id == RuleCollectionIdentifier.typingSounds }?.isEnabled ?? false
            isKeycapColorwayEnabled = collections.first { $0.id == RuleCollectionIdentifier.keycapColorway }?.isEnabled ?? false
            updateTapHoldIdleLabels(from: collections)
        }
    }

    // MARK: - Tap-Hold Idle Labels

    private func updateTapHoldIdleLabels(from collections: [RuleCollection]) {
        var labels: [UInt16: String] = [:]
        for collection in collections where collection.isEnabled {
            guard case let .tapHoldPicker(config) = collection.configuration else { continue }
            let output = config.selectedTapOutput ?? config.tapOptions.first?.output
            guard let output, let keyCode = Self.kanataNameToKeyCode(config.inputKey) else { continue }
            if let label = Self.tapHoldOutputDisplayLabel(output) {
                labels[keyCode] = label
            }
        }
        tapHoldIdleLabels = labels
    }

    /// Get display label for tap-hold output.
    /// Uses the centralized KeyDisplayFormatter utility.
    private static func tapHoldOutputDisplayLabel(_ output: String) -> String? {
        KeyDisplayFormatter.tapHoldLabel(for: output)
    }

    /// Pre-load all icons for launcher mode and layer-based app launches
    /// Call on startup to ensure icons are cached before user enters launcher mode
    private func preloadAllIcons() {
        Task {
            // Load collections once for both preload methods
            let collections = await RuleCollectionStore.shared.loadCollections()

            // Preload launcher grid icons (app icons and favicons)
            await IconResolverService.shared.preloadLauncherIcons()

            // Preload layer-based app/URL icons (Vim leader, etc.)
            await IconResolverService.shared.preloadLayerIcons(from: collections)
        }
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

    /// Start fade-out animation for a released key
    private func startKeyFadeOut(_ keyCode: UInt16) {
        // Cancel any existing fade-out for this key
        fadeOutTasks[keyCode]?.cancel()

        // Animate fade from 0 (visible) to 1 (faded) over the duration
        let duration = OverlayTiming.keyReleaseFadeDuration
        let steps = 20 // 20 steps for smooth animation
        let stepDuration = duration / Double(steps)

        let task = Task { @MainActor in
            for step in 1 ... steps {
                guard !Task.isCancelled else {
                    keyFadeAmounts.removeValue(forKey: keyCode)
                    return
                }

                let progress = CGFloat(step) / CGFloat(steps)
                keyFadeAmounts[keyCode] = progress

                try? await Task.sleep(for: .milliseconds(Int(stepDuration * 1000)))
            }

            // Fade complete - clean up
            keyFadeAmounts.removeValue(forKey: keyCode)
            fadeOutTasks.removeValue(forKey: keyCode)
        }

        fadeOutTasks[keyCode] = task
    }

    /// Cancel fade-out for a key that was re-pressed
    private func cancelKeyFadeOut(_ keyCode: UInt16) {
        fadeOutTasks[keyCode]?.cancel()
        fadeOutTasks.removeValue(forKey: keyCode)
        keyFadeAmounts.removeValue(forKey: keyCode)
    }

    // MARK: - Private Event Handling

    private func startIdleMonitor() {
        idleMonitorTask?.cancel()
        lastInteraction = Date()

        idleMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(idlePollInterval))

                // Check TCP connection state (detects disconnection via timeout)
                checkTcpConnectionState()

                // Don't fade while holding a momentary layer key (non-base layer active)
                let isOnMomentaryLayer = currentLayerName.lowercased() != "base"
                if isOnMomentaryLayer {
                    // Keep overlay fully visible while on a non-base layer
                    if fadeAmount != 0 { fadeAmount = 0 }
                    if deepFadeAmount != 0 { deepFadeAmount = 0 }
                    continue
                }

                let elapsed = Date().timeIntervalSince(lastInteraction)

                // Stage 1: outline fade begins after idleTimeout, completes over 5s
                // Use pow(x, 0.7) easing so changes are faster initially and gentler at the end,
                // avoiding the perceptual "cliff" when linear formulas hit their endpoints together.
                let linearProgress = max(0, min(1, (elapsed - idleTimeout) / 5))
                let fadeProgress = pow(linearProgress, 0.7)
                if fadeProgress != fadeAmount {
                    fadeAmount = fadeProgress
                }

                // Stage 2: deep fade to 5% after deepFadeTimeout over deepFadeRamp seconds
                let deepProgress = max(0, min(1, (elapsed - deepFadeTimeout) / deepFadeRamp))
                if deepProgress != deepFadeAmount {
                    deepFadeAmount = deepProgress
                }
            }
        }
    }

    /// Reset idle timer and un-fade if necessary.
    func noteInteraction() {
        lastInteraction = Date()
        if fadeAmount != 0 { fadeAmount = 0 }
        if deepFadeAmount != 0 { deepFadeAmount = 0 }
    }

    /// Track that we received a TCP event (for connection state indicator)
    private func noteTcpEventReceived() {
        lastTcpEventTime = Date()
        if !isKanataConnected {
            isKanataConnected = true
            AppLogger.shared.log("🌐 [KeyboardViz] Kanata TCP connected (received event)")
        }
    }

    /// Check TCP connection timeout (called from idle monitor)
    private func checkTcpConnectionState() {
        guard let lastEvent = lastTcpEventTime else {
            // No events ever received - not connected
            if isKanataConnected {
                isKanataConnected = false
                AppLogger.shared.log("🌐 [KeyboardViz] Kanata TCP disconnected (no events)")
            }
            return
        }

        let elapsed = Date().timeIntervalSince(lastEvent)
        if elapsed > tcpConnectionTimeout, isKanataConnected {
            isKanataConnected = false
            AppLogger.shared.log("🌐 [KeyboardViz] Kanata TCP disconnected (timeout after \(String(format: "%.1f", elapsed))s)")
        }
    }

    // MARK: - Layout Management

    /// Update the physical keyboard layout and rebuild key mappings
    /// - Parameter newLayout: The new physical layout to use
    func setLayout(_ newLayout: PhysicalLayout) {
        guard layout.id != newLayout.id else { return }
        AppLogger.shared.info("🎹 [KeyboardViz] Layout changed: \(layout.id) -> \(newLayout.id)")
        layout = newLayout
        rebuildLayerMapping() // Rebuild mappings with new layout
    }

    // MARK: - Layer Mapping

    /// Update the current layer and rebuild key mapping
    func updateLayer(_ layerName: String) {
        let wasLauncherMode = isLauncherModeActive

        // IMPORTANT: Don't update currentLayerName yet - wait until mapping is ready
        // This prevents UI flash where old mapping shows with new layer name
        let targetLayerName = layerName

        // Clear tap-hold sources on layer change to prevent stale suppressions
        // (e.g., user switches layers while holding a tap-hold key)
        activeTapHoldSources.removeAll()

        // Check if we'll be entering/exiting launcher mode
        let willBeLauncherMode = targetLayerName.lowercased() == Self.launcherLayerName

        // Load/clear launcher mappings when entering/exiting launcher mode
        if willBeLauncherMode, !wasLauncherMode {
            loadLauncherMappings()
        } else if !willBeLauncherMode, wasLauncherMode {
            launcherMappings.removeAll()
        }

        // Reset idle timer on any layer change (including returning to base)
        noteInteraction()
        noteTcpEventReceived()

        // Build mapping first, then update layer name atomically when ready
        rebuildLayerMappingForLayer(targetLayerName)
    }

    /// Load launcher mappings from the Quick Launcher rule collection
    func loadLauncherMappings() {
        Task { @MainActor in
            let collections = await RuleCollectionStore.shared.loadCollections()

            // Find the launcher collection and extract its mappings
            guard let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
                  let config = launcherCollection.configuration.launcherGridConfig
            else {
                AppLogger.shared.debug("🚀 [KeyboardViz] No launcher config found")
                return
            }

            // Build key -> mapping dictionary (lowercase key names)
            // Filter out apps that aren't installed on this system
            let enabledMappings = config.mappings.filter { mapping in
                guard mapping.isEnabled else { return false }

                // URLs are always included (browser handles them)
                if case .url = mapping.target { return true }

                // Apps: check if installed
                if case let .app(name, bundleId) = mapping.target {
                    let isInstalled = Self.isAppInstalled(name: name, bundleId: bundleId)
                    if !isInstalled {
                        AppLogger.shared.debug("🚀 [KeyboardViz] Skipping \(name) - not installed")
                    }
                    return isInstalled
                }

                return true
            }

            launcherMappings = Dictionary(
                uniqueKeysWithValues: enabledMappings.map { ($0.key.lowercased(), $0) }
            )

            AppLogger.shared.info("🚀 [KeyboardViz] Loaded \(launcherMappings.count) launcher mappings (filtered for installed apps)")
        }
    }

    /// Check if an app is installed on the system
    private static func isAppInstalled(name: String, bundleId: String?) -> Bool {
        // Try bundle ID first (most reliable)
        if let bundleId, NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
            return true
        }

        // Fall back to app name in /Applications
        let directPath = "/Applications/\(name).app"
        if FileManager.default.fileExists(atPath: directPath) {
            return true
        }

        // Try capitalized name
        let capitalizedPath = "/Applications/\(name.capitalized).app"
        if FileManager.default.fileExists(atPath: capitalizedPath) {
            return true
        }

        return false
    }

    /// Rebuild the key mapping for the current layer
    func rebuildLayerMapping() {
        rebuildLayerMappingForLayer(currentLayerName)
    }

    /// Rebuild the key mapping for a specific layer
    /// Updates both the layer name and mapping atomically to prevent UI flash
    private func rebuildLayerMappingForLayer(_ targetLayerName: String) {
        // Cancel any in-flight mapping task
        layerMapTask?.cancel()

        // Skip in test environment
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug("🧪 [KeyboardViz] Skipping layer mapping in test environment")
            return
        }

        isLoadingLayerMap = true
        AppLogger.shared.info("🗺️ [KeyboardViz] Starting layer mapping build for '\(targetLayerName)'...")

        layerMapTask = Task { [weak self] in
            guard let self else { return }

            do {
                let configPath = WizardSystemPaths.userConfigPath
                AppLogger.shared.debug("🗺️ [KeyboardViz] Using config: \(configPath)")

                // Load rule collections for collection ownership tracking
                let ruleCollections = await RuleCollectionStore.shared.loadCollections()

                // Build mapping for target layer
                var mapping = try await layerKeyMapper.getMapping(
                    for: targetLayerName,
                    configPath: configPath,
                    layout: layout,
                    collections: ruleCollections
                )

                // DEBUG: Log what simulator returned
                AppLogger.shared.info("🗺️ [KeyboardViz] Simulator returned \(mapping.count) entries for '\(targetLayerName)'")
                for (keyCode, info) in mapping.prefix(20) {
                    AppLogger.shared.debug("  [\(targetLayerName)] keyCode \(keyCode) -> '\(info.displayLabel)'")
                }

                // Augment mapping with push-msg actions from custom rules and rule collections
                // Only include actions targeting this specific layer
                let customRules = await CustomRulesStore.shared.loadRules()
                AppLogger.shared.info("🗺️ [KeyboardViz] Augmenting '\(targetLayerName)' with \(customRules.count) custom rules and \(ruleCollections.count) collections")
                mapping = augmentWithPushMsgActions(
                    mapping: mapping,
                    customRules: customRules,
                    ruleCollections: ruleCollections,
                    currentLayerName: targetLayerName
                )

                // Apply app-specific overrides for the current frontmost app
                mapping = await applyAppSpecificOverrides(to: mapping)

                // Update layer name and mapping atomically to prevent UI flash
                // This ensures the UI never shows mismatched layer name + old mapping
                await MainActor.run {
                    self.objectWillChange.send()
                    self.currentLayerName = targetLayerName
                    self.layerKeyMap = mapping
                    self.remapOutputMap = self.buildRemapOutputMap(from: mapping)
                    self.isLoadingLayerMap = false
                    AppLogger.shared
                        .info("🗺️ [KeyboardViz] Updated currentLayerName to '\(targetLayerName)' and layerKeyMap with \(mapping.count) entries, remapOutputMap with \(self.remapOutputMap.count) remaps")
                }

                AppLogger.shared.info("🗺️ [KeyboardViz] Built layer mapping for '\(targetLayerName)': \(mapping.count) keys")

                // Log a few sample mappings for debugging
                for (keyCode, info) in mapping.prefix(5) {
                    AppLogger.shared.debug("  keyCode \(keyCode) -> '\(info.displayLabel)'")
                }
            } catch {
                AppLogger.shared.error("❌ [KeyboardViz] Failed to build layer mapping: \(error)")
                await MainActor.run {
                    self.isLoadingLayerMap = false
                }
            }
        }
    }

    /// Build a map from input keyCode -> output keyCode for simple remaps.
    /// Used to suppress output key highlighting when the input key is pressed.
    /// - Parameter mapping: The layer key mapping to extract remap info from
    /// - Returns: Dictionary mapping input keyCodes to their output keyCodes
    private func buildRemapOutputMap(from mapping: [UInt16: LayerKeyInfo]) -> [UInt16: UInt16] {
        var result: [UInt16: UInt16] = [:]
        for (inputKeyCode, info) in mapping {
            guard let outputKeyCode = info.outputKeyCode,
                  outputKeyCode != inputKeyCode, // Only actual remaps (A->B, not A->A)
                  !info.isTransparent // Transparent keys pass through, not remaps
            else {
                continue
            }
            result[inputKeyCode] = outputKeyCode
        }
        return result
    }

    /// Augment layer mapping with push-msg actions from custom rules and rule collections
    /// Handles app launches, system actions, and other push-msg patterns
    /// - Parameters:
    ///   - mapping: The base layer key mapping from the simulator
    ///   - customRules: Custom rules to check for push-msg patterns
    ///   - ruleCollections: Preset rule collections to check for push-msg patterns
    ///   - currentLayerName: The layer name to filter collections/rules by (only include matching layers)
    /// - Returns: Mapping with action info added where applicable
    private func augmentWithPushMsgActions(
        mapping: [UInt16: LayerKeyInfo],
        customRules: [CustomRule],
        ruleCollections: [RuleCollection],
        currentLayerName: String
    ) -> [UInt16: LayerKeyInfo] {
        var augmented = mapping

        // Build lookups from input key -> LayerKeyInfo
        var actionByInput: [String: LayerKeyInfo] = [:]

        // First, process rule collections (lower priority - can be overridden by custom rules)
        // Only process collections that target the current layer or base layer
        for collection in ruleCollections where collection.isEnabled {
            // Check if this collection targets the current layer
            let collectionLayerName = collection.targetLayer.kanataName.lowercased()
            let currentLayer = currentLayerName.lowercased()

            // Only include mappings from collections targeting this layer
            // Exception: base layer gets base-layer collections only
            guard collectionLayerName == currentLayer else {
                AppLogger.shared.debug("🗺️ [KeyboardViz] Skipping collection '\(collection.name)' (targets '\(collectionLayerName)', current layer '\(currentLayer)')")
                continue
            }

            AppLogger.shared.debug("🗺️ [KeyboardViz] Including collection '\(collection.name)' (\(collection.mappings.count) mappings)")

            for keyMapping in collection.mappings {
                let input = keyMapping.input.lowercased()
                // First try push-msg pattern (apps, system actions, URLs)
                if let info = Self.extractPushMsgInfo(from: keyMapping.output, description: keyMapping.description) {
                    actionByInput[input] = info
                } else {
                    // Simple key remap
                    let outputKey = keyMapping.output.lowercased()
                    if let outputKeyCode = Self.kanataNameToKeyCode(outputKey) {
                        let displayLabel = outputKey.count == 1 ? outputKey.uppercased() : outputKey.capitalized
                        actionByInput[input] = .mapped(
                            displayLabel: displayLabel,
                            outputKey: outputKey,
                            outputKeyCode: outputKeyCode
                        )
                    }
                }
            }
        }

        // Then, process custom rules (higher priority - overrides collections)
        for rule in customRules where rule.isEnabled {
            // Check if this rule targets the current layer
            let ruleLayerName = rule.targetLayer.kanataName.lowercased()
            let currentLayer = currentLayerName.lowercased()

            // Only include rules targeting this layer
            guard ruleLayerName == currentLayer else {
                continue
            }

            let input = rule.input.lowercased()
            // First try push-msg pattern (apps, system actions, URLs)
            if let info = Self.extractPushMsgInfo(from: rule.output, description: rule.notes) {
                actionByInput[input] = info
            } else {
                // Simple key remap (e.g., "a" -> "b") or media key (e.g., "brup", "volu")
                let outputKey = rule.output.lowercased()

                // Check if this is a known system action/media key (brup, volu, pp, etc.)
                // If so, create a systemAction LayerKeyInfo so the SF Symbol renders correctly
                if let systemAction = SystemActionInfo.find(byOutput: outputKey) {
                    actionByInput[input] = .systemAction(
                        action: systemAction.id,
                        description: systemAction.name
                    )
                } else if let outputKeyCode = Self.kanataNameToKeyCode(outputKey) {
                    // Regular key remap (e.g., "a" -> "b")
                    let displayLabel = outputKey.count == 1 ? outputKey.uppercased() : outputKey.capitalized
                    actionByInput[input] = .mapped(
                        displayLabel: displayLabel,
                        outputKey: outputKey,
                        outputKeyCode: outputKeyCode
                    )
                }
            }
        }

        AppLogger.shared.info("🗺️ [KeyboardViz] Found \(actionByInput.count) actions (push-msg + simple remaps)")

        // Update mapping entries
        // IMPORTANT: Only augment keys that are NOT transparent (XX)
        // Transparent keys should pass through without showing action labels
        for (keyCode, originalInfo) in mapping {
            let keyName = OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
            if let info = actionByInput[keyName] {
                // Skip augmentation if the original key is transparent (XX)
                // Transparent keys should not show action labels from collections/rules
                if originalInfo.isTransparent {
                    AppLogger.shared.debug("🗺️ [KeyboardViz] Skipping augmentation for transparent key \(keyName)(\(keyCode))")
                    continue
                }
                augmented[keyCode] = info
                AppLogger.shared.debug("🗺️ [KeyboardViz] Key \(keyName)(\(keyCode)) -> '\(info.displayLabel)'")
            }
        }

        return augmented
    }

    // MARK: - Cached Regex Patterns

    /// Cached regex for extracting push-msg type:value patterns
    /// Pattern: (push-msg "type:value")
    private nonisolated static let pushMsgTypeValueRegex = try! NSRegularExpression(
        pattern: #"\(push-msg\s+\"([^:\"]+):([^\"]+)\"\)"#,
        options: []
    )

    /// Cached regex for extracting app launch identifiers
    /// Pattern: (push-msg "launch:AppName")
    private nonisolated static let pushMsgLaunchRegex = try! NSRegularExpression(
        pattern: #"\(push-msg\s+\"launch:([^\"]+)\"\)"#,
        options: []
    )

    /// Cached regex for extracting URL identifiers
    /// Pattern: (push-msg "open:domain.com")
    private nonisolated static let pushMsgOpenRegex = try! NSRegularExpression(
        pattern: #"\(push-msg\s+\"open:([^\"]+)\"\)"#,
        options: []
    )

    /// Extract LayerKeyInfo from a push-msg output string
    /// Handles: launch:, system:, and generic push-msg patterns
    nonisolated static func extractPushMsgInfo(from output: String, description: String?) -> LayerKeyInfo? {
        guard let match = pushMsgTypeValueRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let typeRange = Range(match.range(at: 1), in: output),
              let valueRange = Range(match.range(at: 2), in: output)
        else {
            return nil
        }

        let msgType = String(output[typeRange])
        let msgValue = String(output[valueRange])

        switch msgType {
        case "launch":
            return .appLaunch(appIdentifier: msgValue)
        case "system":
            // Use description if available, otherwise format the system action
            let displayLabel = description ?? Self.systemActionDisplayLabel(msgValue)
            return .systemAction(action: msgValue, description: displayLabel)
        default:
            // Generic push-msg - use description or message value
            return .pushMsg(message: description ?? msgValue)
        }
    }

    /// Get a human-readable label for a system action
    nonisolated static func systemActionDisplayLabel(_ action: String) -> String {
        switch action.lowercased() {
        case "dnd", "do-not-disturb", "donotdisturb", "focus":
            "Do Not Disturb"
        case "spotlight":
            "Spotlight"
        case "dictation":
            "Dictation"
        case "mission-control", "missioncontrol":
            "Mission Control"
        case "launchpad":
            "Launchpad"
        case "notification-center", "notificationcenter":
            "Notification Center"
        case "siri":
            "Siri"
        default:
            action.capitalized
        }
    }

    /// Get a human-readable label for media/function keys (returns nil if not a recognized media key)
    /// These labels match what LabelMetadata.sfSymbol(forOutputLabel:) expects for icon lookup
    nonisolated static func mediaKeyDisplayLabel(_ kanataKey: String) -> String? {
        switch kanataKey.lowercased() {
        case "brup": "Brightness Up"
        case "brdn", "brdown": "Brightness Down"
        case "volu": "Volume Up"
        case "vold", "voldwn": "Volume Down"
        case "mute": "Mute"
        case "pp": "Play/Pause"
        case "next": "Next Track"
        case "prev": "Previous Track"
        default: nil
        }
    }

    /// Extract app identifier from a push-msg launch output string
    /// - Parameter output: The kanata output string (e.g., "(push-msg \"launch:Safari\")")
    /// - Returns: The app identifier if this is a launch action, nil otherwise
    nonisolated static func extractAppLaunchIdentifier(from output: String) -> String? {
        guard let match = pushMsgLaunchRegex.firstMatch(
            in: output,
            range: NSRange(output.startIndex..., in: output)
        ),
            let range = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        return String(output[range])
    }

    /// Extract URL from a push-msg open output string
    /// - Parameter output: The kanata output string (e.g., "(push-msg \"open:github.com\")")
    /// - Returns: The URL string if this is an open action, nil otherwise
    nonisolated static func extractUrlIdentifier(from output: String) -> String? {
        guard let match = pushMsgOpenRegex.firstMatch(
            in: output,
            range: NSRange(output.startIndex..., in: output)
        ),
            let range = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        return String(output[range])
    }

    /// Invalidate cached mappings (call when config changes)
    func invalidateLayerMappings() {
        AppLogger.shared.info("🔔 [KeyboardViz] invalidateLayerMappings called - will rebuild layer mapping for '\(currentLayerName)'")
        AppLogger.shared.info("🔔 [KeyboardViz] Current layerKeyMap has \(layerKeyMap.count) entries, keyCode 0 = '\(layerKeyMap[0]?.displayLabel ?? "nil")'")
        Task {
            await layerKeyMapper.invalidateCache()
            AppLogger.shared.info("🔔 [KeyboardViz] Cache invalidated, now calling rebuildLayerMapping()")
            rebuildLayerMapping()
        }
    }

    // MARK: - TCP Key Input Handling

    /// Set up observer for Kanata TCP KeyInput events (physical key presses)
    private func setupKeyInputObserver() {
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
    private func setupTcpHeartbeatObserver() {
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
    private func setupHoldActivatedObserver() {
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
    private func setupTapActivatedObserver() {
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
    private func setupMessagePushObserver() {
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
    private func setupRuleCollectionsObserver() {
        ruleCollectionsObserver = NotificationCenter.default.addObserver(
            forName: .ruleCollectionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.loadFeatureCollectionStates()
                // Re-preload icons when collections change (cache warming for new mappings)
                self.preloadAllIcons()
                AppLogger.shared.debug("⌨️ [KeyboardViz] Reloaded feature collection states and icons after change")
            }
        }
        AppLogger.shared.debug("⌨️ [KeyboardViz] Rule collections observer registered")
    }

    /// Set up observer for one-shot modifier activations
    private func setupOneShotObserver() {
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
    private func setupAppContextObserver() {
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
    private func handleAppContextChange(bundleId: String?) async {
        // Skip if app hasn't actually changed
        guard bundleId != currentAppBundleId else { return }
        currentAppBundleId = bundleId

        AppLogger.shared.info("🔄 [KeyboardViz] App context changed: \(bundleId ?? "nil")")

        // Rebuild layer mapping to include/exclude app-specific overrides
        rebuildLayerMapping()
    }

    /// Apply app-specific overrides to the layer key map.
    /// Returns a new map with overrides applied for the current app.
    private func applyAppSpecificOverrides(to baseMap: [UInt16: LayerKeyInfo]) async -> [UInt16: LayerKeyInfo] {
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
    private func formatOutputForDisplay(_ output: String) -> String {
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
    private func handleOneShotActivated(modifiers: String) {
        noteTcpEventReceived()
        // Parse comma-separated modifiers (e.g., "lsft" or "lsft,lctl")
        let mods = modifiers.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        for mod in mods {
            activeOneShotModifiers.insert(mod)
        }
        AppLogger.shared.info("⚡ [KeyboardViz] One-shot activated: \(modifiers) → active: \(activeOneShotModifiers)")
    }

    /// Clear one-shot modifiers (called after next key press)
    private func clearOneShotModifiers() {
        guard !activeOneShotModifiers.isEmpty else { return }
        AppLogger.shared.info("⚡ [KeyboardViz] Clearing one-shot modifiers: \(activeOneShotModifiers)")
        activeOneShotModifiers.removeAll()
    }

    /// Handle a MessagePush event from Kanata (icon/emphasis commands)
    /// Format: "icon:arrow-left", "emphasis:h,j,k,l", "emphasis:clear"
    private func handleMessagePush(_ message: String) {
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

        AppLogger.shared.debug("📨 [KeyboardViz] Unhandled push message: \(message)")
    }

    /// Handle a HoldActivated event from Kanata
    private func handleHoldActivated(key: String, action: String) {
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
    private func handleTapActivated(key: String, action: String) {
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
    private func handleTcpKeyInput(key: String, action: String) {
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
           let mappedOutput = remapOutputMap.first(where: { $0.value == keyCode }) {
            AppLogger.shared.debug(
                "🔄 [KeyboardViz] KeyInput \(key)(\(keyCode)): isRemapOutput=true, sourceKey=\(mappedOutput.key), tcpPressed=\(pressedKeyCodes), remapSources=\(activeRemapSourceKeyCodes), suppressedRemapOutputs=\(suppressedRemapOutputKeyCodes), isRemapSuppressed=\(isRemapSuppressed)"
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

    // MARK: - Test hooks (DEBUG only)

    /// Simulate a HoldActivated TCP event (used by unit tests).
    func simulateHoldActivated(key: String, action: String) {
        handleHoldActivated(key: key, action: action)
    }

    /// Simulate a TapActivated TCP event (used by unit tests).
    func simulateTapActivated(key: String, action: String) {
        handleTapActivated(key: key, action: action)
    }

    /// Simulate a TCP KeyInput event (used by unit tests).
    func simulateTcpKeyInput(key: String, action: String) {
        handleTcpKeyInput(key: key, action: action)
    }

    /// Maps Kanata key names (e.g., "h", "j", "space") to macOS key codes
    /// This is the inverse of OverlayKeyboardView.keyCodeToKanataName()
    nonisolated static func kanataNameToKeyCode(_ name: String) -> UInt16? {
        // Map from lowercase Kanata key names to macOS virtual key codes
        let mapping: [String: UInt16] = [
            // Row 3: Home row (ASDF...)
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
            // Row 4: Bottom row (ZXCV...)
            "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
            // Row 2: Top row (QWERTY...)
            "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            // Row 1: Number row
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
            "equal": 24, "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29,
            // More top row keys
            "rightbrace": 30, "o": 31, "u": 32, "leftbrace": 33, "i": 34, "p": 35,
            // Home row continued
            "enter": 36, "ret": 36, "return": 36,
            "l": 37, "j": 38, "apostrophe": 39, "k": 40, "semicolon": 41, "backslash": 42,
            // Bottom row continued
            "comma": 43, "slash": 44, "n": 45, "m": 46, "dot": 47,
            // Special keys
            "tab": 48, "space": 49, "spc": 49, "grave": 50, "grv": 50,
            "backspace": 51, "bspc": 51, "esc": 53, "escape": 53,
            // Modifiers
            "rightmeta": 54, "rmet": 54, "leftmeta": 55, "lmet": 55,
            "leftshift": 56, "lsft": 56, "capslock": 57, "caps": 57,
            "leftalt": 58, "lalt": 58, "leftctrl": 59, "lctl": 59,
            "rightshift": 60, "rsft": 60, "rightalt": 61, "ralt": 61,
            "fn": 63,
            // Function keys
            "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101,
            "f11": 103, "f10": 109, "f12": 111, "f4": 118, "f2": 120, "f1": 122,
            // Arrow keys
            "left": 123, "right": 124, "down": 125, "up": 126,
            // Navigation keys
            "home": 115,
            "pageup": 116, "pgup": 116,
            "del": 117, "delete": 117,
            "end": 119,
            "pagedown": 121, "pgdn": 121,
            "help": 114, "insert": 114,
            // Extended function keys
            "f13": 105,
            "f14": 107,
            "f15": 113,
            "f16": 106,
            "f17": 64,
            "f18": 79,
            "f19": 80,
            // Right Control
            "rightctrl": 102, "rctl": 102,
            // ISO key (between Left Shift and Z on ISO keyboards)
            "intlbackslash": 10,
            // ABNT2 key (between slash and right shift on Brazilian keyboards)
            "intlro": 94,
            // Korean language keys
            "hangeul": 104, "hanja": 104
        ]
        return mapping[name.lowercased()]
    }
}
