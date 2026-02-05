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
    var fadeOutTasks: [UInt16: Task<Void, Never>] = [:]

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
    var holdActiveKeyCodes: Set<UInt16> = []
    /// Custom icons for keys set via push-msg (keyCode -> icon name)
    /// Example: "arrow-left", "safari", "home"
    @Published var customIcons: [UInt16: String] = [:]
    /// Most recently pressed key (for icon association)
    var lastPressedKeyCode: UInt16?
    /// Icon clear tasks (keyCode -> task that clears the icon)
    var iconClearTasks: [UInt16: Task<Void, Never>] = [:]
    /// Keys emphasized via push-msg emphasis command
    /// Example: (push-msg "emphasis:h,j,k,l") sets HJKL as emphasized
    @Published var customEmphasisKeyCodes: Set<UInt16> = []

    // MARK: - Launcher Mode State

    /// Layer name that triggers launcher mode display
    static let launcherLayerName = "launcher"

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

    // MARK: - TCP Connection State

    /// Whether Kanata TCP server is responding (based on receiving events)
    /// When false, overlay shows "not connected" indicator
    @Published var isKanataConnected: Bool = false

    /// Last time we received any TCP event (for connection timeout detection)
    var lastTcpEventTime: Date?

    /// How long without events before we consider disconnected (seconds)
    let tcpConnectionTimeout: TimeInterval = 3.0

    // MARK: - One-Shot Modifier State

    /// Active one-shot modifiers (modifier key names like "lsft", "lctl")
    /// Cleared on next key press after activation
    @Published var activeOneShotModifiers: Set<String> = []

    /// One-shot modifier key codes for visual highlighting
    /// Maps modifier name to keyCode (e.g., "lsft" -> 56)
    static let oneShotModifierKeyCodes: [String: UInt16] = [
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
    var resolvingHoldLabels: Set<UInt16> = []
    /// Short-lived cache of resolved hold labels to avoid repeated simulator runs (keyCode -> (label, timestamp))
    var holdLabelCache: [UInt16: (label: String, timestamp: Date)] = [:]
    /// Cache time-to-live in seconds
    let holdLabelCacheTTL: TimeInterval = 5
    /// Pending delayed clears for hold-active keys to tolerate tap-hold-press jitter
    var holdClearWorkItems: [UInt16: DispatchWorkItem] = [:]

    // MARK: - Tap-Hold Output Suppression

    /// Dynamically tracks tap-hold source keys to their tap output keys.
    /// Populated when TapActivated events are received from Kanata.
    /// Example: capslock (57) -> esc (53) when TapActivated says key=caps, action=esc
    var dynamicTapHoldOutputMap: [UInt16: Set<UInt16>] = [:]

    /// Output keyCodes that should be temporarily suppressed due to recent tap activation.
    /// Populated when TapActivated fires (since the source key may already be released).
    /// Auto-cleared after a brief delay.
    var recentTapOutputs: Set<UInt16> = []

    /// Pending tasks to clear tap outputs from temporary suppression
    var tapOutputClearTasks: [UInt16: Task<Void, Never>] = [:]

    /// Fallback static map for common tap-hold patterns (used when TapActivated not available).
    /// Will be phased out once TapActivated is fully deployed.
    static let fallbackTapHoldOutputMap: [UInt16: Set<UInt16>] = [
        57: [53] // capslock -> esc (common tap-hold: caps = tap:esc, hold:hyper)
    ]

    /// Source keys that are currently pressed (for output suppression).
    /// While a source key is in this set, its mapped output keys won't be added to pressedKeyCodes.
    var activeTapHoldSources: Set<UInt16> = []

    /// All output keyCodes that should be suppressed (computed from active sources)
    var suppressedOutputKeyCodes: Set<UInt16> {
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
    var remapOutputMap: [UInt16: UInt16] = [:]

    /// Output keyCodes to suppress from currently-pressed remapped keys.
    /// When A->B is mapped and A is pressed, B should not light up separately.
    var suppressedRemapOutputKeyCodes: Set<UInt16> {
        activeRemapSourceKeyCodes.reduce(into: Set<UInt16>()) { result, inputKeyCode in
            if let outputKeyCode = remapOutputMap[inputKeyCode] {
                result.insert(outputKeyCode)
            }
        }
    }

    /// Recently released remap source keys kept briefly to suppress delayed outputs.
    var recentRemapSourceKeyCodes: Set<UInt16> = []
    /// Pending tasks to clear remap sources from temporary suppression.
    var remapSourceClearTasks: [UInt16: Task<Void, Never>] = [:]

    /// Remap sources that should participate in suppression (pressed + recent releases).
    var activeRemapSourceKeyCodes: Set<UInt16> {
        pressedKeyCodes.union(recentRemapSourceKeyCodes)
    }

    func shouldSuppressKeyHighlight(_ keyCode: UInt16, source: String = "unknown") -> Bool {
        let tapHoldSuppressed = suppressedOutputKeyCodes.contains(keyCode)
        let remapSuppressed = suppressedRemapOutputKeyCodes.contains(keyCode)
        let recentTapSuppressed = recentTapOutputs.contains(keyCode)
        let shouldSuppress = tapHoldSuppressed || remapSuppressed || recentTapSuppressed

        if FeatureFlags.keyboardSuppressionDebugEnabled, shouldSuppress {
            AppLogger.shared.debug(
                """
                🧯 [KeyboardViz] Suppressed keyCode=\(keyCode) source=\(source) \
                tapHold=\(tapHoldSuppressed) remap=\(remapSuppressed) \
                recentTap=\(recentTapSuppressed) remapSources=\(activeRemapSourceKeyCodes)
                """
            )
        }

        return shouldSuppress
    }

    /// Key input notification observer
    var keyInputObserver: Any?
    /// TCP heartbeat notification observer (layer polling)
    var tcpHeartbeatObserver: Any?
    /// Hold activated notification observer
    var holdActivatedObserver: Any?
    /// Tap activated notification observer
    var tapActivatedObserver: Any?
    /// Push message notification observer (for icon/emphasis messages)
    var messagePushObserver: Any?
    /// Rule collections changed notification observer (for feature toggle updates)
    var ruleCollectionsObserver: Any?
    /// One-shot activated notification observer
    var oneShotObserver: Any?
    /// App context change subscription (for app-specific key overrides)
    var appContextCancellable: AnyCancellable?
    /// Current app's bundle identifier for overlay updates
    var currentAppBundleId: String?

    // MARK: - Key Emphasis

    /// HJKL key codes for nav layer auto-emphasis (computed once from key names)
    static let hjklKeyCodes: Set<UInt16> = ["h", "j", "k", "l"].compactMap { kanataNameToKeyCode($0) }.reduce(into: Set<UInt16>()) { $0.insert($1) }

    /// Key codes to emphasize based on current layer and custom emphasis commands
    /// HJKL keys are auto-emphasized when on nav layer, plus any custom emphasis via push-msg
    var emphasizedKeyCodes: Set<UInt16> {
        // Auto-emphasis: HJKL on nav layer, but only when those keys are actually mapped.
        let autoEmphasis: Set<UInt16> = {
            guard currentLayerName.lowercased() == "nav" else { return [] }
            return Self.hjklKeyCodes.filter { keyCode in
                guard let info = layerKeyMap[keyCode] else { return false }
                return !info.isTransparent
            }
            .reduce(into: Set<UInt16>()) { $0.insert($1) }
        }()

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
    let layerKeyMapper = LayerKeyMapper()
    /// Task for building layer mapping
    var layerMapTask: Task<Void, Never>?

    var isCapturing = false
    var idleMonitorTask: Task<Void, Never>?
    var lastInteraction: Date = .init()

    let idleTimeout: TimeInterval = 10
    let deepFadeTimeout: TimeInterval = 48
    let deepFadeRamp: TimeInterval = 2
    let idlePollInterval: TimeInterval = 0.25

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

    /// Load enabled states for optional feature collections (Typing Sounds)
    func loadFeatureCollectionStates() {
        Task { @MainActor in
            let collections = await RuleCollectionStore.shared.loadCollections()
            isTypingSoundsEnabled = collections.first { $0.id == RuleCollectionIdentifier.typingSounds }?.isEnabled ?? false
            updateTapHoldIdleLabels(from: collections)
        }
    }

    // MARK: - Tap-Hold Idle Labels

    func updateTapHoldIdleLabels(from collections: [RuleCollection]) {
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
    static func tapHoldOutputDisplayLabel(_ output: String) -> String? {
        KeyDisplayFormatter.tapHoldLabel(for: output)
    }

    /// Pre-load all icons for launcher mode and layer-based app launches
    /// Call on startup to ensure icons are cached before user enters launcher mode
    func preloadAllIcons() {
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
    func startKeyFadeOut(_ keyCode: UInt16) {
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
    func cancelKeyFadeOut(_ keyCode: UInt16) {
        fadeOutTasks[keyCode]?.cancel()
        fadeOutTasks.removeValue(forKey: keyCode)
        keyFadeAmounts.removeValue(forKey: keyCode)
    }

}
