import AppKit
import Carbon
import Foundation
import KeyPathCore
import SwiftUI

/// ViewModel for keyboard visualization that tracks pressed keys
@MainActor
class KeyboardVisualizationViewModel: ObservableObject {
    /// Key codes pressed according to CGEvent tap (post-Kanata transformed events)
    @Published var pressedKeyCodes: Set<UInt16> = []
    /// Key codes pressed according to Kanata TCP KeyInput events (physical/raw input)
    @Published var tcpPressedKeyCodes: Set<UInt16> = []
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
    /// Key mapping for the current layer: keyCode -> LayerKeyInfo
    @Published var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
    /// Hold labels for tap-hold keys that have transitioned to hold state
    /// Maps keyCode -> hold display label (e.g., "✦" for Hyper)
    @Published var holdLabels: [UInt16: String] = [:]
    /// Keys currently in a hold-active state (set when HoldActivated fires).
    /// Used to keep the key visually pressed even if tap-hold implementations
    /// emit spurious release/press events while held.
    private var holdActiveKeyCodes: Set<UInt16> = []
    /// Custom icons for keys set via push-msg (keyCode -> icon name)
    /// Example: "arrow-left", "safari", "home"
    @Published var customIcons: [UInt16: String] = [:]
    /// Keys emphasized via push-msg emphasis command
    /// Example: (push-msg "emphasis:h,j,k,l") sets HJKL as emphasized
    @Published var customEmphasisKeyCodes: Set<UInt16> = []
    /// Tracks keys currently undergoing async hold-label resolution to avoid duplicate simulator runs
    private var resolvingHoldLabels: Set<UInt16> = []
    /// Short-lived cache of resolved hold labels to avoid repeated simulator runs (keyCode -> (label, timestamp))
    private var holdLabelCache: [UInt16: (label: String, timestamp: Date)] = [:]
    /// Cache time-to-live in seconds
    private let holdLabelCacheTTL: TimeInterval = 5
    /// Pending delayed clears for hold-active keys to tolerate tap-hold-press jitter
    private var holdClearWorkItems: [UInt16: DispatchWorkItem] = [:]
    /// Key input notification observer
    private var keyInputObserver: Any?
    /// Hold activated notification observer
    private var holdActivatedObserver: Any?
    /// Push message notification observer (for icon/emphasis messages)
    private var messagePushObserver: Any?

    // MARK: - Key Emphasis

    /// HJKL key codes for nav layer auto-emphasis (computed once from key names)
    private static let hjklKeyCodes: Set<UInt16> = {
        ["h", "j", "k", "l"].compactMap { kanataNameToKeyCode($0) }.reduce(into: Set<UInt16>()) { $0.insert($1) }
    }()

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
        tcpPressedKeyCodes.union(holdActiveKeyCodes)
    }

    /// Service for building layer key mappings
    private let layerKeyMapper = LayerKeyMapper()
    /// Task for building layer mapping
    private var layerMapTask: Task<Void, Never>?

    // Event tap for listening to keyDown and keyUp events
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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
            AppLogger.shared.debug("🧪 [KeyboardViz] Test environment - skipping event tap")
            return
        }

        // Check permissions silently
        guard AXIsProcessTrusted() else {
            AppLogger.shared.warn("⚠️ [KeyboardViz] Accessibility permission required")
            return
        }

        setupEventTap()
        setupKeyInputObserver() // Listen for TCP-based physical key events
        setupHoldActivatedObserver() // Listen for tap-hold state transitions
        setupMessagePushObserver() // Listen for icon/emphasis push messages
        startIdleMonitor()
        rebuildLayerMapping() // Build initial layer mapping
    }

    func stopCapturing() {
        guard isCapturing else { return }

        isCapturing = false
        pressedKeyCodes.removeAll()
        tcpPressedKeyCodes.removeAll()
        holdLabels.removeAll()
        holdLabelCache.removeAll()

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        if let observer = keyInputObserver {
            NotificationCenter.default.removeObserver(observer)
            keyInputObserver = nil
        }

        if let observer = holdActivatedObserver {
            NotificationCenter.default.removeObserver(observer)
            holdActivatedObserver = nil
        }

        if let observer = messagePushObserver {
            NotificationCenter.default.removeObserver(observer)
            messagePushObserver = nil
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

    private func setupEventTap() {
        // Listen to keyDown, keyUp, and flagsChanged (for modifier keys like Caps Lock)
        let eventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly, // Listen-only mode - don't interfere with other apps
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let viewModel = Unmanaged<KeyboardVisualizationViewModel>.fromOpaque(refcon)
                    .takeUnretainedValue()

                viewModel.handleKeyEvent(event: event, type: type)

                // Always pass event through (listen-only mode)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            AppLogger.shared.error("❌ [KeyboardViz] Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isCapturing = true

        AppLogger.shared.info("✅ [KeyboardViz] Event tap created (listen-only mode)")
    }

    private func handleKeyEvent(event: CGEvent, type: CGEventType) {
        // Ignore autorepeat frames
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
            return
        }

        noteInteraction()

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        Task { @MainActor in
            switch type {
            case .keyDown:
                cancelKeyFadeOut(keyCode) // Cancel any ongoing fade-out
                pressedKeyCodes.insert(keyCode)
                TypingSoundsManager.shared.playKeydown()
                AppLogger.shared.debug("⌨️ [KeyboardViz] KeyDown: \(keyCode)")

            case .keyUp:
                pressedKeyCodes.remove(keyCode)
                startKeyFadeOut(keyCode) // Start fade-out animation
                TypingSoundsManager.shared.playKeyup()
                AppLogger.shared.debug("⌨️ [KeyboardViz] KeyUp: \(keyCode)")

            case .flagsChanged:
                // Handle modifier key presses (Caps Lock, Shift, Cmd, etc.)
                handleFlagsChanged(event: event, keyCode: keyCode)

            default:
                break
            }
        }
    }

    /// Handle modifier key state changes from flagsChanged events
    private func handleFlagsChanged(event: CGEvent, keyCode: UInt16) {
        let flags = event.flags

        // Update only the modifier key that triggered this flagsChanged event so previously-held
        // modifiers stay pressed (e.g., holding ⌘ while pressing ⌥).
        switch keyCode {
        case 57: // Caps Lock
            updateModifierState(keyCode: 57, isPressed: flags.contains(.maskAlphaShift))
        case 56: // Left Shift
            updateModifierState(keyCode: 56, isPressed: flags.contains(.maskShift))
        case 60: // Right Shift
            updateModifierState(keyCode: 60, isPressed: flags.contains(.maskShift))
        case 59: // Left Control
            updateModifierState(keyCode: 59, isPressed: flags.contains(.maskControl))
        case 55: // Left Command
            updateModifierState(keyCode: 55, isPressed: flags.contains(.maskCommand))
        case 54: // Right Command
            updateModifierState(keyCode: 54, isPressed: flags.contains(.maskCommand))
        case 58: // Left Option
            updateModifierState(keyCode: 58, isPressed: flags.contains(.maskAlternate))
        case 61: // Right Option
            updateModifierState(keyCode: 61, isPressed: flags.contains(.maskAlternate))
        case 63: // Fn key
            updateModifierState(keyCode: 63, isPressed: flags.contains(.maskSecondaryFn))
        default:
            break
        }

        // Final reconciliation: if a modifier flag is absent, ensure both sides of that modifier
        // are cleared so simultaneous releases don't leave a side stuck as "pressed".
        reconcileModifierStates(flags: flags)

        AppLogger.shared.debug("⌨️ [KeyboardViz] FlagsChanged: keyCode=\(keyCode), flags=\(flags.rawValue)")
    }

    private func startIdleMonitor() {
        idleMonitorTask?.cancel()
        lastInteraction = Date()

        idleMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(idlePollInterval))

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

    // MARK: - Layer Mapping

    /// Update the current layer and rebuild key mapping
    func updateLayer(_ layerName: String) {
        currentLayerName = layerName
        // Reset idle timer on any layer change (including returning to base)
        noteInteraction()
        rebuildLayerMapping()
    }

    /// Rebuild the key mapping for the current layer
    func rebuildLayerMapping() {
        // Cancel any in-flight mapping task
        layerMapTask?.cancel()

        // Skip in test environment
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug("🧪 [KeyboardViz] Skipping layer mapping in test environment")
            return
        }

        isLoadingLayerMap = true
        AppLogger.shared.info("🗺️ [KeyboardViz] Starting layer mapping build for '\(currentLayerName)'...")

        layerMapTask = Task { [weak self] in
            guard let self else { return }

            do {
                let configPath = WizardSystemPaths.userConfigPath
                AppLogger.shared.debug("🗺️ [KeyboardViz] Using config: \(configPath)")

                // Build mapping for current layer
                var mapping = try await layerKeyMapper.getMapping(
                    for: currentLayerName,
                    configPath: configPath
                )

                // Augment mapping with push-msg actions from custom rules and rule collections
                // Skip augmentation on base layer - base should show normal key labels
                if currentLayerName.lowercased() != "base" {
                    let customRules = await CustomRulesStore.shared.loadRules()
                    let ruleCollections = await RuleCollectionStore.shared.loadCollections()
                    AppLogger.shared.info("🗺️ [KeyboardViz] Augmenting with \(customRules.count) custom rules and \(ruleCollections.count) collections")
                    mapping = augmentWithPushMsgActions(
                        mapping: mapping,
                        customRules: customRules,
                        ruleCollections: ruleCollections
                    )
                } else {
                    AppLogger.shared.debug("🗺️ [KeyboardViz] Skipping push-msg augmentation on base layer")
                }

                // Update on main actor
                await MainActor.run {
                    self.layerKeyMap = mapping
                    self.isLoadingLayerMap = false
                }

                AppLogger.shared.info("🗺️ [KeyboardViz] Built layer mapping for '\(currentLayerName)': \(mapping.count) keys")

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

    /// Augment layer mapping with push-msg actions from custom rules and rule collections
    /// Handles app launches, system actions, and other push-msg patterns
    /// - Parameters:
    ///   - mapping: The base layer key mapping from the simulator
    ///   - customRules: Custom rules to check for push-msg patterns
    ///   - ruleCollections: Preset rule collections to check for push-msg patterns
    /// - Returns: Mapping with action info added where applicable
    private func augmentWithPushMsgActions(
        mapping: [UInt16: LayerKeyInfo],
        customRules: [CustomRule],
        ruleCollections: [RuleCollection]
    ) -> [UInt16: LayerKeyInfo] {
        var augmented = mapping

        // Build lookups from input key -> LayerKeyInfo
        var actionByInput: [String: LayerKeyInfo] = [:]

        // First, process rule collections (lower priority - can be overridden by custom rules)
        for collection in ruleCollections where collection.isEnabled {
            for keyMapping in collection.mappings {
                let input = keyMapping.input.lowercased()
                if let info = Self.extractPushMsgInfo(from: keyMapping.output, description: keyMapping.description) {
                    actionByInput[input] = info
                }
            }
        }

        // Then, process custom rules (higher priority - overrides collections)
        for rule in customRules where rule.isEnabled {
            let input = rule.input.lowercased()
            if let info = Self.extractPushMsgInfo(from: rule.output, description: rule.notes) {
                actionByInput[input] = info
            }
        }

        AppLogger.shared.info("🗺️ [KeyboardViz] Found \(actionByInput.count) push-msg actions")

        // Update mapping entries
        for (keyCode, _) in mapping {
            let keyName = OverlayKeyboardView.keyCodeToKanataName(keyCode).lowercased()
            if let info = actionByInput[keyName] {
                augmented[keyCode] = info
                AppLogger.shared.debug("🗺️ [KeyboardViz] Key \(keyName)(\(keyCode)) -> '\(info.displayLabel)'")
            }
        }

        return augmented
    }

    // MARK: - Cached Regex Patterns

    /// Cached regex for extracting push-msg type:value patterns
    /// Pattern: (push-msg "type:value")
    nonisolated(unsafe) private static let pushMsgTypeValueRegex = try! NSRegularExpression(
        pattern: #"\(push-msg\s+\"([^:\"]+):([^\"]+)\"\)"#,
        options: []
    )

    /// Cached regex for extracting app launch identifiers
    /// Pattern: (push-msg "launch:AppName")
    nonisolated(unsafe) private static let pushMsgLaunchRegex = try! NSRegularExpression(
        pattern: #"\(push-msg\s+\"launch:([^\"]+)\"\)"#,
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

    /// Invalidate cached mappings (call when config changes)
    func invalidateLayerMappings() {
        Task {
            await layerKeyMapper.invalidateCache()
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

    /// Handle a MessagePush event from Kanata (icon/emphasis commands)
    /// Format: "icon:arrow-left", "emphasis:h,j,k,l", "emphasis:clear"
    private func handleMessagePush(_ message: String) {
        // Parse icon messages: "icon:arrow-left"
        if message.hasPrefix("icon:") {
            let iconName = String(message.dropFirst(5)) // Remove "icon:" prefix
            AppLogger.shared.info("🎨 [KeyboardViz] Icon message: \(iconName)")
            // TODO: Associate icon with most recently pressed key
            // For now, just log - need key context to apply icon
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

        switch action {
        case "press", "repeat":
            cancelKeyFadeOut(keyCode) // Cancel any ongoing fade-out
            tcpPressedKeyCodes.insert(keyCode)
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
            AppLogger.shared.debug("⌨️ [KeyboardViz] TCP KeyPress: \(key) -> keyCode \(keyCode)")
        case "release":
            tcpPressedKeyCodes.remove(keyCode)
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
                "🧪 [KeyboardViz] caps state: tcpPressed=\(tcpPressedKeyCodes.contains(57)) holdActive=\(holdActiveKeyCodes.contains(57)) holdLabel=\(holdLabels[57] ?? "nil")"
            )
        }
    }

    // MARK: - Test hooks (DEBUG only)

    /// Simulate a HoldActivated TCP event (used by unit tests).
    func simulateHoldActivated(key: String, action: String) {
        handleHoldActivated(key: key, action: action)
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
            // Delete key (forward delete)
            "del": 117, "delete": 117
        ]
        return mapping[name.lowercased()]
    }

    /// Clear modifier keycodes when the corresponding flag is fully released.
    private func reconcileModifierStates(flags: CGEventFlags) {
        if !flags.contains(.maskCommand) {
            pressedKeyCodes.remove(55) // Left Command
            pressedKeyCodes.remove(54) // Right Command
        }
        if !flags.contains(.maskAlternate) {
            pressedKeyCodes.remove(58) // Left Option
            pressedKeyCodes.remove(61) // Right Option
        }
        if !flags.contains(.maskShift) {
            pressedKeyCodes.remove(56) // Left Shift
            pressedKeyCodes.remove(60) // Right Shift
        }
        if !flags.contains(.maskControl) {
            pressedKeyCodes.remove(59) // Left Control
            pressedKeyCodes.remove(62) // Right Control (defensive)
        }
        if !flags.contains(.maskAlphaShift) {
            pressedKeyCodes.remove(57) // Caps Lock
        }
        if !flags.contains(.maskSecondaryFn) {
            pressedKeyCodes.remove(63) // Fn key
        }
    }

    #if DEBUG
        /// Test helper to simulate a flagsChanged event without installing an event tap.
        func simulateFlagsChanged(flags: CGEventFlags, keyCode: UInt16) {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
                return
            }
            event.flags = flags
            handleKeyEvent(event: event, type: .flagsChanged)
        }
    #endif

    private func updateModifierState(keyCode: UInt16, isPressed: Bool) {
        if isPressed {
            pressedKeyCodes.insert(keyCode)
        } else {
            pressedKeyCodes.remove(keyCode)
        }
    }
}
