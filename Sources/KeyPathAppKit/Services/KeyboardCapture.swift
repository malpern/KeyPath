import AppKit
import Carbon
import Foundation
import KeyPathCore
import SwiftUI

// Import the event processing infrastructure
#if canImport(KeyPath)
    // This is to handle potential circular dependencies during build
#endif

@MainActor
public class KeyboardCapture: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var captureCallback: ((String) -> Void)?
    private var sequenceCallback: ((KeySequence) -> Void)?
    private var isCapturing = false
    private var isContinuous = false
    private(set) var suppressEvents = true // default: suppress during raw capture (exposed for tests)
    private var pauseTimer: Timer?
    private let pauseDuration: TimeInterval = 2.0 // 2 seconds pause to auto-stop
    private var noEventTimer: Timer?
    private var receivedAnyEvent = false
    private var noKeyBreadcrumbTimer: Timer?
    private var anyEventSeen = false

    // Enhanced sequence capture properties
    private var captureMode: CaptureMode = .single
    private var capturedKeys: [KeyPress] = []
    private let chordWindow: TimeInterval = 0.05 // 50ms window for chord detection
    private let sequenceTimeout: TimeInterval = 2.0 // 2 seconds for sequence completion
    private var lastKeyTime: Date?
    private var chordTimer: Timer?
    private var sequenceTimer: Timer?
    private var localMonitor: Any?
    private var lastCapturedKey: KeyPress?
    private var lastCaptureAt: Date?
    private let dedupWindow: TimeInterval = 0.04 // 40ms
    private var currentTapLocation: CGEventTapLocation = .cgSessionEventTap

    /// Event router for processing captured events through the event processing chain
    private var eventRouter: EventRouter?

    /// Enable/disable event router integration (for backward compatibility)
    /// Default: false to maintain legacy behavior and avoid CGEvent tap conflicts
    public var useEventRouter: Bool = false

    /// Reference to RuntimeCoordinator to check if Kanata is running (to avoid tap conflicts)
    private weak var kanataManager: RuntimeCoordinator?

    /// Activity observer for logging keyboard shortcuts
    private weak var activityObserver: KeyboardActivityObserver?

    // Fast process probe to reduce race with manager.isRunning updates
    private func fastProbeKanataRunning(timeout: TimeInterval = 0.25) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "kanata"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return false
        }
        // Kill if it takes too long
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if task.isRunning { task.terminate() }
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Event Router Configuration

    /// Set the event router for processing captured events
    func setEventRouter(_ router: EventRouter?, kanataManager: RuntimeCoordinator? = nil) {
        eventRouter = router
        self.kanataManager = kanataManager
        AppLogger.shared.log(
            "📋 [KeyboardCapture] Event router \(router != nil ? "enabled" : "disabled")")
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
            "📊 [KeyboardCapture] Activity observer \(observer != nil ? "enabled" : "disabled")")
    }

    // Emergency stop sequence detection
    private var emergencyEventTap: CFMachPort?
    private var emergencyRunLoopSource: CFRunLoopSource?
    private var emergencyCallback: (() -> Void)?
    private var isMonitoringEmergency = false
    private var pressedKeys: Set<Int64> = []

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
                    "⚠️ [KeyboardCapture] Accessibility permission missing - triggering wizard")
            } else {
                AppLogger.shared.log(
                    "🧪 [KeyboardCapture] Skipping wizard trigger in test environment")
            }
            return
        }

        currentTapLocation = .cgSessionEventTap
        setupEventTap(at: currentTapLocation)

        // Fallback to HID listen-only if nothing arrives quickly in listen-only mode
        if !suppressEvents {
            noEventTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if !self.receivedAnyEvent {
                        AppLogger.shared.log(
                            "🎹 [KeyboardCapture] No events at session tap; switching to HID listen-only")
                        self.reinstallTap(to: .cghidEventTap)
                    }
                }
            }
        }
    }

    private func startCaptureAfterPermissions(callback: @escaping (String) -> Void) {
        captureCallback = callback
        isCapturing = true
        isContinuous = false

        currentTapLocation = .cgSessionEventTap
        setupEventTap(at: currentTapLocation)

        if !suppressEvents {
            noEventTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if !self.receivedAnyEvent {
                        AppLogger.shared.log(
                            "🎹 [KeyboardCapture] No events at session tap; switching to HID listen-only")
                        self.reinstallTap(to: .cghidEventTap)
                    }
                }
            }
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
                    "🧪 [KeyboardCapture] Skipping wizard trigger (continuous) in test environment")
            }
            return
        }

        setupEventTap()
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
        // This avoids redundant checks and prevents UI blocking
        // Determine capture mode. Prefer listen-only if the service is running to
        // avoid competing intercepting taps. Re-check process table to reduce race risk.
        var listenOnly = FeatureFlags.captureListenOnlyEnabled && fastProbeKanataRunning()
        if FeatureFlags.captureListenOnlyEnabled, listenOnly == false {
            // Fast secondary probe to reduce race conditions with UI state
            if fastProbeKanataRunning() { listenOnly = true }
        }
        suppressEvents = !listenOnly
        receivedAnyEvent = false
        anyEventSeen = false
        noEventTimer?.invalidate()
        noEventTimer = nil
        AppLogger.shared.log(
            "🎹 [KeyboardCapture] Starting \(mode) capture (tap=\(listenOnly ? "listenOnly" : "defaultTap/suppress"), kanataRunning=\(listenOnly))"
        )

        // Install a local keyDown monitor to (a) prevent the audible beep in this app
        // and (b) guarantee immediate UI feedback even if the global tap is delayed.
        // This only affects KeyPath while recording, not other apps.
        if localMonitor == nil {
            AppLogger.shared.log(
                "🎹 [KeyboardCapture] Installing local keyDown monitor for recording (swallow only)")
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in
                // Swallow the key to avoid system beep while recording, but do NOT
                // feed it into the capture pipeline to prevent duplicate events.
                nil
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
                            "⏱️ [KeyboardCapture] No key events received after 1.0s (mode=\(self.captureMode), tap=\(self.suppressEvents ? "defaultTap" : "listenOnly"), location=\(self.currentTapLocation))"
                        )
                }
            }
        }
        setupEventTap()
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
    }

    private func setupEventTap(at location: CGEventTapLocation = .cgSessionEventTap) {
        // In tests (including CI), avoid creating CGEvent taps to prevent hangs and permission prompts
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug(
                "🧪 [KeyboardCapture] Test environment detected – skipping CGEvent tap setup")
            return
        }
        let eventMask = (1 << CGEventType.keyDown.rawValue)
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
                        capture.handleKeyEvent(processedEvent)
                    }
                    // Allow event to pass in listen-only mode; suppress otherwise
                    return capture.suppressEvents ? nil : Unmanaged.passUnretained(event)
                } else {
                    // Legacy behavior - process directly
                    capture.handleKeyEvent(event)
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
            "✅ [KeyboardCapture] Event tap created (location=\(location), options=\(tapDesc))")
    }

    private func reinstallTap(to newLocation: CGEventTapLocation) {
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        currentTapLocation = newLocation
        setupEventTap(at: newLocation)
    }

    private func handleKeyEvent(_ event: CGEvent) {
        // Ignore autorepeat frames
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let keyName = keyCodeToString(keyCode)
        let modifiers = ModifierSet(cgEventFlags: event.flags)
        let now = Date()

        AppLogger.shared.log(
            "🎹 [KeyboardCapture] keyDown: \(keyName) code=\(keyCode) suppress=\(suppressEvents)")
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

    private func processKeyPress(_ keyPress: KeyPress) {
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

    private func resetPauseTimer() {
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
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "return",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "space",
            50: "`", 51: "delete", 53: "escape", 58: "caps", 59: "caps"
        ]

        if let keyName = keyMap[keyCode] {
            return keyName
        } else {
            return "key\(keyCode)"
        }
    }

    // Check permissions without prompting - using synchronous method to avoid deadlocks
    func checkAccessibilityPermissionsSilently() -> Bool {
        // Use direct API call instead of async PermissionOracle to avoid semaphore deadlock
        AXIsProcessTrusted()
    }

    // Public method to explicitly request permissions (for use in wizard)
    func requestPermissionsExplicitly() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Emergency Stop Sequence Detection

    func startEmergencyMonitoring(callback: @escaping () -> Void) {
        guard !isMonitoringEmergency else { return }

        // Avoid event taps in test/CI to prevent hangs
        if TestEnvironment.isRunningTests {
            AppLogger.shared.debug(
                "🧪 [KeyboardCapture] Test environment – skipping emergency monitoring tap")
            return
        }

        // Safety check: avoid CGEvent tap conflicts when Kanata is running
        // Per ADR-006, emergency monitoring should also respect the single tap rule
        // BUT: Emergency stop is a safety feature, so we allow it even when Kanata is running
        // The emergency tap uses a different location (CGEventTapLocation.cghidEventTap) which
        // should not conflict with Kanata's tap
        // Note: Emergency monitoring is critical for safety, so we prioritize it over ADR-006
        if fastProbeKanataRunning() {
            AppLogger.shared.log(
                "⚠️ [KeyboardCapture] Emergency monitoring enabled even while Kanata is running (safety override)"
            )
        }

        emergencyCallback = callback
        isMonitoringEmergency = true

        // Only start monitoring if we already have permissions
        // Don't prompt for permissions - let the wizard handle that
        if !checkAccessibilityPermissionsSilently() {
            // Silently fail - we'll start monitoring once permissions are granted
            isMonitoringEmergency = false
            return
        }

        setupEmergencyEventTap()
    }

    func stopEmergencyMonitoring() {
        guard isMonitoringEmergency else { return }

        isMonitoringEmergency = false
        pressedKeys.removeAll()

        if let source = emergencyRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            emergencyRunLoopSource = nil
        }

        if let tap = emergencyEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            emergencyEventTap = nil
        }
    }

    private func setupEmergencyEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        emergencyEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly, // ADR-006: Use listen-only for emergency monitoring
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                let capture = Unmanaged<KeyboardCapture>.fromOpaque(refcon!).takeUnretainedValue()
                capture.handleEmergencyEvent(event: event, type: type)
                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let eventTap = emergencyEventTap else {
            AppLogger.shared.error("❌ [KeyboardCapture] Failed to create emergency event tap")
            return
        }

        emergencyRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), emergencyRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleEmergencyEvent(event: CGEvent, type: CGEventType) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Key codes for the emergency sequence: Ctrl (59), Space (49), Esc (53)
        let leftControlKey: Int64 = 59
        let spaceKey: Int64 = 49
        let escapeKey: Int64 = 53

        if type == .keyDown {
            pressedKeys.insert(keyCode)

            // Check if all three keys are pressed simultaneously
            if pressedKeys.contains(leftControlKey),
               pressedKeys.contains(spaceKey),
               pressedKeys.contains(escapeKey) {
                AppLogger.shared.log("🚨 [Emergency] Kanata emergency stop sequence detected!")

                DispatchQueue.main.async {
                    self.emergencyCallback?()
                }

                // Clear the set to prevent repeated triggers
                pressedKeys.removeAll()
            }
        } else if type == .keyUp {
            pressedKeys.remove(keyCode)
        }
    }
}
