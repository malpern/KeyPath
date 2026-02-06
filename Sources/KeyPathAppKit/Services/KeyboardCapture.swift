import AppKit
import Carbon
import Combine
import Foundation
import KeyPathCore

// Import the event processing infrastructure
#if canImport(KeyPath)
    // This is to handle potential circular dependencies during build
#endif

@MainActor
public class KeyboardCapture: ObservableObject {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var captureCallback: ((String) -> Void)?
    var sequenceCallback: ((KeySequence) -> Void)?
    var isCapturing = false
    var isContinuous = false
    private(set) var suppressEvents = true // default: suppress during raw capture (exposed for tests)
    var pauseTimer: Timer?
    let pauseDuration: TimeInterval = 2.0 // 2 seconds pause to auto-stop
    var noKeyBreadcrumbTimer: Timer?
    var anyEventSeen = false

    // TCP-based capture for when Kanata is running
    var tcpKeyInputObserver: NSObjectProtocol?
    var isTcpCaptureMode = false

    // Enhanced sequence capture properties
    var captureMode: CaptureMode = .single
    var capturedKeys: [KeyPress] = []
    let chordWindow: TimeInterval = 0.05 // 50ms window for chord detection
    let sequenceTimeout: TimeInterval = 2.0 // 2 seconds for sequence completion
    var lastKeyTime: Date?
    var chordTimer: Timer?
    var sequenceTimer: Timer?
    var localMonitor: Any?
    var mediaKeyMonitor: Any?
    var lastCapturedKey: KeyPress?
    var lastCaptureAt: Date?
    let dedupWindow: TimeInterval = 0.04 // 40ms
    var currentTapLocation: CGEventTapLocation = .cgSessionEventTap
    var pressedModifierKeyCodes: Set<Int64> = []

    /// Event router for processing captured events through the event processing chain
    var eventRouter: EventRouter?

    /// Enable/disable event router integration (for backward compatibility)
    /// Default: false to maintain legacy behavior and avoid CGEvent tap conflicts
    public var useEventRouter: Bool = false

    /// Reference to RuntimeCoordinator to check if Kanata is running (to avoid tap conflicts)
    weak var kanataManager: RuntimeCoordinator?

    /// Activity observer for logging keyboard shortcuts
    weak var activityObserver: KeyboardActivityObserver?

    /// Non-blocking check for whether Kanata is running, using cached service state.
    /// Replaces the old blocking `pgrep` call that could stall the main actor.
    func fastProbeKanataRunning(timeout _: TimeInterval = 0.25) -> Bool {
        KanataService.shared.state.isRunning
    }

    // MARK: - Event Router Configuration

    /// Set the event router for processing captured events
    func setEventRouter(_ router: EventRouter?, kanataManager: RuntimeCoordinator? = nil) {
        eventRouter = router
        self.kanataManager = kanataManager
        AppLogger.shared.log(
            "📋 [KeyboardCapture] Event router \(router != nil ? "enabled" : "disabled")"
        )
    }

    /// Enable event router integration with the default router
    public func enableEventRouter() {
        // Note: We avoid importing defaultEventRouter here to prevent circular dependencies
        // Instead, it should be set externally via setEventRouter()
        useEventRouter = true
        AppLogger.shared.log("📋 [KeyboardCapture] Event router integration enabled")
    }

    /// Disable event router integration (fallback to legacy behavior)
    public func disableEventRouter() {
        useEventRouter = false
        AppLogger.shared.log("📋 [KeyboardCapture] Event router integration disabled")
    }

    // MARK: - Activity Logging

    /// Set the activity observer for logging keyboard shortcuts
    public func setActivityObserver(_ observer: KeyboardActivityObserver?) {
        activityObserver = observer
        AppLogger.shared.log(
            "📊 [KeyboardCapture] Activity observer \(observer != nil ? "enabled" : "disabled")"
        )
    }

    // Emergency stop sequence detection
    var emergencyEventTap: CFMachPort?
    var emergencyRunLoopSource: CFRunLoopSource?
    var emergencyCallback: (() -> Void)?
    var isMonitoringEmergency = false
    var pressedKeys: Set<Int64> = []

    func startCapture(callback: @escaping (String) -> Void) {
        guard !isCapturing else { return }

        if FeatureFlags.useJustInTimePermissionRequests {
            Task { @MainActor in
                await PermissionGate.shared.checkAndRequestPermissions(
                    for: .keyCapture,
                    onGranted: { [weak self] in
                        guard let self else { return }
                        startCaptureAfterPermissions(callback: callback)
                    },
                    onDenied: {
                        callback("⚠️ Accessibility permission required")
                    }
                )
            }
            return
        }

        captureCallback = callback
        isCapturing = true
        isContinuous = false

        // Only start capture if we already have permissions
        // Don't prompt for permissions - let the wizard handle that
        if !checkAccessibilityPermissionsSilently() {
            // Notify that we need permissions - this should trigger the wizard
            isCapturing = false
            captureCallback = nil
            callback("⚠️ Accessibility permission required")

            // In unit tests, avoid posting UI-triggering notifications
            if !TestEnvironment.isRunningTests {
                // Trigger the wizard to help user fix permissions
                NotificationCenter.default.post(
                    name: NSNotification.Name("KeyboardCapturePermissionNeeded"),
                    object: nil,
                    userInfo: ["reason": "Accessibility permission required for keyboard capture"]
                )

                AppLogger.shared.log(
                    "⚠️ [KeyboardCapture] Accessibility permission missing - triggering wizard"
                )
            } else {
                AppLogger.shared.log(
                    "🧪 [KeyboardCapture] Skipping wizard trigger in test environment"
                )
            }
            return
        }

        // Use TCP-based capture when Kanata is running, otherwise CGEvent
        if fastProbeKanataRunning() {
            setupTcpCapture()
        } else {
            currentTapLocation = .cgSessionEventTap
            setupEventTap(at: currentTapLocation)
        }
    }

    private func startCaptureAfterPermissions(callback: @escaping (String) -> Void) {
        captureCallback = callback
        isCapturing = true
        isContinuous = false

        // Use TCP-based capture when Kanata is running, otherwise CGEvent
        if fastProbeKanataRunning() {
            setupTcpCapture()
        } else {
            currentTapLocation = .cgSessionEventTap
            setupEventTap(at: currentTapLocation)
        }
    }

    func startContinuousCapture(callback: @escaping (String) -> Void) {
        guard !isCapturing else { return }

        captureCallback = callback
        isCapturing = true
        isContinuous = true

        // Only start capture if we already have permissions
        // Don't prompt for permissions - let the wizard handle that
        if !checkAccessibilityPermissionsSilently() {
            // Notify that we need permissions - this should trigger the wizard
            isCapturing = false
            isContinuous = false
            captureCallback = nil
            callback("⚠️ Accessibility permission required")

            if !TestEnvironment.isRunningTests {
                // Trigger the wizard to help user fix permissions
                NotificationCenter.default.post(
                    name: NSNotification.Name("KeyboardCapturePermissionNeeded"),
                    object: nil,
                    userInfo: ["reason": "Accessibility permission required for continuous keyboard capture"]
                )

                AppLogger.shared.log(
                    "⚠️ [KeyboardCapture] Accessibility permission missing for continuous capture - triggering wizard"
                )
            } else {
                AppLogger.shared.log(
                    "🧪 [KeyboardCapture] Skipping wizard trigger (continuous) in test environment"
                )
            }
            return
        }

        // Use TCP-based capture when Kanata is running, otherwise CGEvent
        if fastProbeKanataRunning() {
            setupTcpCapture()
        } else {
            setupEventTap()
        }
    }

    /// Enhanced capture method that supports different capture modes
    func startSequenceCapture(mode: CaptureMode, callback: @escaping (KeySequence) -> Void) {
        guard !isCapturing else { return }

        captureMode = mode
        sequenceCallback = callback
        capturedKeys = []
        lastKeyTime = nil
        isCapturing = true
        isContinuous = (mode == .sequence)

        // Trust the caller to have validated permissions before calling this method
        // Determine capture mode. Use TCP when Kanata is running to avoid tap conflicts.
        let kanataRunning = fastProbeKanataRunning()
        suppressEvents = !kanataRunning // Only suppress when not using TCP mode
        anyEventSeen = false
        AppLogger.shared.log(
            "🎹 [KeyboardCapture] Starting \(mode) capture (mode=\(kanataRunning ? "TCP" : "CGEvent"), kanataRunning=\(kanataRunning))"
        )

        // Install a local keyDown monitor to (a) prevent the audible beep in this app
        // and (b) guarantee immediate UI feedback even if the global tap is delayed.
        // This only affects KeyPath while recording, not other apps.
        if localMonitor == nil {
            AppLogger.shared.log(
                "🎹 [KeyboardCapture] Installing local keyDown monitor for recording (swallow only)"
            )
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in
                // Swallow the key to avoid system beep while recording, but do NOT
                // feed it into the capture pipeline to prevent duplicate events.
                nil
            }
        }

        // Install a global monitor for media keys (volume, brightness, play/pause, etc.)
        // These come through as systemDefined events, not regular keyDown events.
        if mediaKeyMonitor == nil {
            AppLogger.shared.log("🎹 [KeyboardCapture] Installing media key monitor")
            mediaKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
                Task { @MainActor in
                    self?.handleMediaKeyEvent(event)
                }
            }
        }
        // Breadcrumb if no events arrive within 1s
        noKeyBreadcrumbTimer?.invalidate()
        noKeyBreadcrumbTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isCapturing, !self.anyEventSeen {
                    AppLogger.shared
                        .log(
                            "⏱️ [KeyboardCapture] No key events received after 1.0s (mode=\(self.captureMode), captureMode=\(self.isTcpCaptureMode ? "TCP" : "CGEvent"))"
                        )
                }
            }
        }

        // Use TCP when Kanata is running to avoid tap conflicts
        if kanataRunning {
            setupTcpCapture()
        } else {
            setupEventTap()
        }
    }

    func stopCapture() {
        guard isCapturing else { return }

        isCapturing = false
        isContinuous = false
        suppressEvents = true
        captureCallback = nil
        sequenceCallback = nil
        capturedKeys = []
        lastKeyTime = nil

        // Cancel all timers
        pauseTimer?.invalidate()
        pauseTimer = nil
        chordTimer?.invalidate()
        chordTimer = nil
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        noKeyBreadcrumbTimer?.invalidate()
        noKeyBreadcrumbTimer = nil

        // Clean up TCP capture mode
        if let observer = tcpKeyInputObserver {
            NotificationCenter.default.removeObserver(observer)
            tcpKeyInputObserver = nil
        }
        isTcpCaptureMode = false

        // Clean up CGEvent tap
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        // Remove local monitor if present
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // Remove media key monitor if present
        if let monitor = mediaKeyMonitor {
            NSEvent.removeMonitor(monitor)
            mediaKeyMonitor = nil
        }

        pressedModifierKeyCodes.removeAll()
    }

    private func setupEventTap(at location: CGEventTapLocation = .cgSessionEventTap) {
        // In tests (including CI), avoid creating CGEvent taps to prevent hangs and permission prompts
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug(
                "🧪 [KeyboardCapture] Test environment detected – skipping CGEvent tap setup"
            )
            return
        }
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let tapOptions: CGEventTapOptions = suppressEvents ? .defaultTap : .listenOnly

        eventTap = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: tapOptions,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { tapProxy, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }

                let capture = Unmanaged<KeyboardCapture>.fromOpaque(refcon).takeUnretainedValue()

                // Process through event router if enabled
                if capture.useEventRouter, let router = capture.eventRouter {
                    let result = router.route(
                        event: event,
                        location: .cgSessionEventTap,
                        proxy: tapProxy,
                        scope: .keyboard
                    )

                    // Handle the routing result
                    if let processedEvent = result.processedEvent {
                        capture.handleKeyEvent(processedEvent, type: processedEvent.type)
                    }
                    // Allow event to pass in listen-only mode; suppress otherwise
                    return capture.suppressEvents ? nil : Unmanaged.passUnretained(event)
                } else {
                    // Legacy behavior - process directly
                    capture.handleKeyEvent(event, type: event.type)
                    // Allow event to pass in listen-only mode; suppress otherwise
                    return capture.suppressEvents ? nil : Unmanaged.passUnretained(event)
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            AppLogger.shared.error(
                "❌ [KeyboardCapture] Failed to create event tap (options=\(tapOptions == .listenOnly ? "listenOnly" : "defaultTap"))"
            )

            // Cleanly end capture state so UI doesn't appear stuck
            isCapturing = false
            isContinuous = false

            // Cancel timers
            pauseTimer?.invalidate()
            pauseTimer = nil
            chordTimer?.invalidate()
            chordTimer = nil
            sequenceTimer?.invalidate()
            sequenceTimer = nil

            // Send a user-facing message via sequence callback if available
            if let cb = sequenceCallback {
                let kp = KeyPress(
                    baseKey: "⚠️ Couldn't start recording", modifiers: [], timestamp: Date(), keyCode: -1
                )
                let seq = KeySequence(keys: [kp], captureMode: .single)
                DispatchQueue.main.async { cb(seq) }
                // Do not nil-out the callback until after dispatch
                sequenceCallback = nil
            } else if let cb = captureCallback {
                DispatchQueue.main.async { cb("⚠️ Couldn't start recording") }
                captureCallback = nil
            }
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        let tapDesc = suppressEvents ? "defaultTap/suppress" : "listenOnly"
        AppLogger.shared.info(
            "✅ [KeyboardCapture] Event tap created (location=\(location), options=\(tapDesc))"
        )
    }

    private func handleKeyEvent(_ event: CGEvent, type: CGEventType) {
        if type == .flagsChanged {
            handleModifierEvent(event)
            return
        }

        guard type == .keyDown else { return }

        // Ignore autorepeat frames
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let keyName = keyCodeToString(keyCode)
        let modifiers = ModifierSet(cgEventFlags: event.flags)
        let now = Date()

        AppLogger.shared.log(
            "🎹 [KeyboardCapture] keyDown: \(keyName) code=\(keyCode) suppress=\(suppressEvents)"
        )
        anyEventSeen = true
        noKeyBreadcrumbTimer?.invalidate()
        noKeyBreadcrumbTimer = nil

        // Create KeyPress
        let keyPress = KeyPress(
            baseKey: keyName,
            modifiers: modifiers,
            timestamp: now,
            keyCode: keyCode
        )

        // Notify activity observer (for logging keyboard shortcuts)
        // This happens before dedup so all shortcuts are captured
        activityObserver?.didReceiveKeyEvent(keyPress)

        // De-dup identical events arriving within a small window
        if let last = lastCapturedKey, let lastAt = lastCaptureAt {
            if last.baseKey == keyPress.baseKey,
               last.modifiers == keyPress.modifiers,
               now.timeIntervalSince(lastAt) <= dedupWindow {
                AppLogger.shared.log("🎹 [KeyboardCapture] Deduped duplicate keyDown: \(keyName)")
                return
            }
        }
        lastCapturedKey = keyPress
        lastCaptureAt = now

        DispatchQueue.main.async {
            // Handle legacy callback if set (for backward compatibility)
            if self.sequenceCallback == nil, let legacyCallback = self.captureCallback {
                legacyCallback(keyName)

                if !self.isContinuous {
                    self.stopCapture()
                } else {
                    self.resetPauseTimer()
                }
                return
            }

            // Handle new sequence capture
            self.processKeyPress(keyPress)
        }
    }

    private func handleModifierEvent(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard modifierForKeyCode(keyCode) != nil || keyCode == 57 else { return }

        // flagsChanged fires for both press and release; only capture presses
        if pressedModifierKeyCodes.contains(keyCode) {
            pressedModifierKeyCodes.remove(keyCode)
            return
        }
        pressedModifierKeyCodes.insert(keyCode)

        let keyName = keyCodeToString(keyCode)
        let now = Date()

        AppLogger.shared.log(
            "🎹 [KeyboardCapture] flagsChanged: \(keyName) code=\(keyCode) suppress=\(suppressEvents)"
        )
        anyEventSeen = true
        noKeyBreadcrumbTimer?.invalidate()
        noKeyBreadcrumbTimer = nil

        let keyPress = KeyPress(
            baseKey: keyName,
            modifiers: [],
            timestamp: now,
            keyCode: keyCode
        )

        activityObserver?.didReceiveKeyEvent(keyPress)

        if let last = lastCapturedKey, let lastAt = lastCaptureAt {
            if last.baseKey == keyPress.baseKey,
               now.timeIntervalSince(lastAt) <= dedupWindow {
                AppLogger.shared.log("🎹 [KeyboardCapture] Deduped duplicate flagsChanged: \(keyName)")
                return
            }
        }
        lastCapturedKey = keyPress
        lastCaptureAt = now

        DispatchQueue.main.async {
            if self.sequenceCallback == nil, let legacyCallback = self.captureCallback {
                legacyCallback(keyName)

                if !self.isContinuous {
                    self.stopCapture()
                } else {
                    self.resetPauseTimer()
                }
                return
            }

            self.processKeyPress(keyPress)
        }
    }

    /// Handle media key events (volume, brightness, play/pause, etc.)
    /// These come through NSEvent.systemDefined, not regular keyDown events.
    private func handleMediaKeyEvent(_ event: NSEvent) {
        guard isCapturing else { return }
        guard event.subtype.rawValue == 8 else { return } // 8 = media key subtype

        // Media key data is encoded in data1:
        // - bits 16-23: key code (NX_KEYTYPE_*)
        // - bit 8: key state (0 = down, 1 = up)
        // - bits 0-7: repeat count
        let data1 = event.data1
        let mediaKeyCode = (data1 & 0x00FF_0000) >> 16
        let keyState = (data1 & 0x0000_0100) >> 8
        let isKeyDown = keyState == 0

        guard isKeyDown else { return } // Only capture key down events

        let keyName = mediaKeyCodeToString(Int(mediaKeyCode))
        guard keyName != nil else { return } // Unknown media key

        let now = Date()
        AppLogger.shared.log("🎹 [KeyboardCapture] mediaKey: \(keyName!) code=\(mediaKeyCode)")
        anyEventSeen = true
        noKeyBreadcrumbTimer?.invalidate()
        noKeyBreadcrumbTimer = nil

        let keyPress = KeyPress(
            baseKey: keyName!,
            modifiers: [],
            timestamp: now,
            keyCode: Int64(mediaKeyCode) + 1000 // Offset to avoid collision with regular keyCodes
        )

        activityObserver?.didReceiveKeyEvent(keyPress)

        // De-dup identical events
        if let last = lastCapturedKey, let lastAt = lastCaptureAt {
            if last.baseKey == keyPress.baseKey,
               now.timeIntervalSince(lastAt) <= dedupWindow {
                AppLogger.shared.log("🎹 [KeyboardCapture] Deduped duplicate mediaKey: \(keyName!)")
                return
            }
        }
        lastCapturedKey = keyPress
        lastCaptureAt = now

        if sequenceCallback == nil, let legacyCallback = captureCallback {
            legacyCallback(keyName!)
            if !isContinuous {
                stopCapture()
            } else {
                resetPauseTimer()
            }
            return
        }

        processKeyPress(keyPress)
    }

    /// Convert NX_KEYTYPE media key code to a string name
    private func mediaKeyCodeToString(_ keyCode: Int) -> String? {
        // NX_KEYTYPE values from IOKit/hidsystem/ev_keymap.h
        let mediaKeyMap: [Int: String] = [
            0: "volumeup", // NX_KEYTYPE_SOUND_UP
            1: "volumedown", // NX_KEYTYPE_SOUND_DOWN
            2: "brightnessup", // NX_KEYTYPE_BRIGHTNESS_UP
            3: "brightnessdown", // NX_KEYTYPE_BRIGHTNESS_DOWN
            7: "mute", // NX_KEYTYPE_MUTE
            16: "playpause", // NX_KEYTYPE_PLAY
            17: "next", // NX_KEYTYPE_NEXT (fast forward)
            18: "previous", // NX_KEYTYPE_PREVIOUS (rewind)
            19: "fastforward", // NX_KEYTYPE_FAST
            20: "rewind", // NX_KEYTYPE_REWIND
            14: "eject", // NX_KEYTYPE_EJECT
            21: "kbillumup", // NX_KEYTYPE_ILLUMINATION_UP
            22: "kbillumdown", // NX_KEYTYPE_ILLUMINATION_DOWN
            23: "kbillumtoggle" // NX_KEYTYPE_ILLUMINATION_TOGGLE
        ]
        return mediaKeyMap[keyCode]
    }

    func processKeyPress(_ keyPress: KeyPress) {
        if !isModifierOnlyKeyPress(keyPress) {
            removeModifierOnlyKeys(matching: keyPress.modifiers)
        }
        let now = keyPress.timestamp

        switch captureMode {
        case .single:
            // Single key - complete immediately
            let sequence = KeySequence(keys: [keyPress], captureMode: .single)
            sequenceCallback?(sequence)
            stopCapture()

        case .chord:
            // Chord detection - look for keys pressed within window
            if let lastTime = lastKeyTime, now.timeIntervalSince(lastTime) <= chordWindow {
                // Add to existing chord
                capturedKeys.append(keyPress)
            } else {
                // Start new chord or single key
                capturedKeys = [keyPress]
            }

            lastKeyTime = now

            // REAL-TIME UPDATE: Invoke callback immediately to show keys as they're pressed
            let provisionalSequence = KeySequence(keys: capturedKeys, captureMode: .chord)
            sequenceCallback?(provisionalSequence)

            // Reset chord timer
            chordTimer?.invalidate()
            chordTimer = Timer.scheduledTimer(withTimeInterval: chordWindow, repeats: false) { _ in
                Task { @MainActor in self.completeChord() }
            }

        case .sequence:
            // Sequence capture - accumulate keys
            capturedKeys.append(keyPress)
            lastKeyTime = now

            // REAL-TIME UPDATE: Invoke callback immediately to show keys as they're pressed
            let provisionalSequence = KeySequence(keys: capturedKeys, captureMode: .sequence)
            sequenceCallback?(provisionalSequence)

            // Reset sequence timer
            sequenceTimer?.invalidate()
            sequenceTimer = Timer.scheduledTimer(withTimeInterval: sequenceTimeout, repeats: false) { _ in
                Task { @MainActor in self.completeSequence() }
            }
        }
    }

    private func isModifierOnlyKeyPress(_ keyPress: KeyPress) -> Bool {
        keyPress.modifiers.isEmpty && modifierForKey(keyPress.baseKey) != nil
    }

    private func removeModifierOnlyKeys(matching modifiers: ModifierSet) {
        guard modifiers.hasModifiers else { return }
        capturedKeys.removeAll { keyPress in
            guard keyPress.modifiers.isEmpty,
                  let modifier = modifierForKey(keyPress.baseKey) else { return false }
            return modifiers.contains(modifier)
        }
    }

    private func modifierForKeyCode(_ keyCode: Int64) -> ModifierSet? {
        switch keyCode {
        case 56, 60: // left/right shift
            .shift
        case 59, 62: // left/right control
            .control
        case 58, 61: // left/right option
            .option
        case 55, 54: // left/right command
            .command
        default:
            nil
        }
    }

    private func modifierForKey(_ baseKey: String) -> ModifierSet? {
        switch baseKey.lowercased() {
        case "lsft", "rsft":
            .shift
        case "lctl", "rctl":
            .control
        case "lalt", "ralt", "lopt", "ropt":
            .option
        case "lmet", "rmet":
            .command
        default:
            nil
        }
    }

    private func completeChord() {
        guard !capturedKeys.isEmpty else { return }

        let sequence = KeySequence(keys: capturedKeys, captureMode: .chord)
        sequenceCallback?(sequence)
        stopCapture()
    }

    private func completeSequence() {
        guard !capturedKeys.isEmpty else { return }

        let sequence = KeySequence(keys: capturedKeys, captureMode: .sequence)
        sequenceCallback?(sequence)
        stopCapture()
    }

    func resetPauseTimer() {
        // Cancel existing timer
        pauseTimer?.invalidate()

        // Start new timer for auto-stop after pause
        pauseTimer = Timer.scheduledTimer(withTimeInterval: pauseDuration, repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                self?.stopCapture()
            }
        }
    }

    private func keyCodeToString(_ keyCode: Int64) -> String {
        // Map common key codes to readable names
        let keyMap: [Int64: String] = [
            // Letters
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 45: "n", 46: "m",
            // Numbers
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
            // Symbols
            24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\",
            43: ",", 44: "/", 47: ".", 50: "`",
            // Control keys
            36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape",
            // Modifiers
            54: "rmet", 55: "lmet", 56: "lsft", 57: "caps", 58: "lalt",
            59: "lctl", 60: "rsft", 61: "ralt", 62: "rctl", 63: "fn",
            // Arrow keys
            123: "left", 124: "right", 125: "down", 126: "up",
            // Navigation
            115: "home", 116: "pageup", 117: "forwarddelete", 119: "end", 121: "pagedown",
            // Function keys
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
            98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
            105: "f13", 107: "f14", 113: "f15", 106: "f16",
            // Numpad
            65: "kp.", 67: "kp*", 69: "kp+", 71: "clear", 75: "kp/", 76: "kpenter",
            78: "kp-", 81: "kp=", 82: "kp0", 83: "kp1", 84: "kp2", 85: "kp3",
            86: "kp4", 87: "kp5", 88: "kp6", 89: "kp7", 91: "kp8", 92: "kp9"
        ]

        if let keyName = keyMap[keyCode] {
            return keyName
        } else {
            return "key\(keyCode)"
        }
    }

    /// Check permissions without prompting - using synchronous method to avoid deadlocks
    func checkAccessibilityPermissionsSilently() -> Bool {
        // Use direct API call instead of async PermissionOracle to avoid semaphore deadlock
        AXIsProcessTrusted()
    }

    /// Public method to explicitly request permissions (for use in wizard)
    func requestPermissionsExplicitly() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }
}
