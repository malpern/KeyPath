import AppKit
import Carbon
import Foundation
import SwiftUI

// Import the event processing infrastructure
#if canImport(KeyPath)
    // This is to handle potential circular dependencies during build
#endif

@Observable
@MainActor
public class KeyboardCapture {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var captureCallback: ((String) -> Void)?
    private var sequenceCallback: ((KeySequence) -> Void)?
    private var isCapturing = false
    private var isContinuous = false
    private var pauseTimer: Timer?
    private let pauseDuration: TimeInterval = 2.0 // 2 seconds pause to auto-stop

    // Enhanced sequence capture properties
    private var captureMode: CaptureMode = .single
    private var capturedKeys: [KeyPress] = []
    private let chordWindow: TimeInterval = 0.05 // 50ms window for chord detection
    private let sequenceTimeout: TimeInterval = 2.0 // 2 seconds for sequence completion
    private var lastKeyTime: Date?
    private var chordTimer: Timer?
    private var sequenceTimer: Timer?

    /// Event router for processing captured events through the event processing chain
    private var eventRouter: EventRouter?

    /// Enable/disable event router integration (for backward compatibility)
    /// Default: false to maintain legacy behavior and avoid CGEvent tap conflicts
    public var useEventRouter: Bool = false

    /// Reference to KanataManager to check if Kanata is running (to avoid tap conflicts)
    private weak var kanataManager: KanataManager?

    // MARK: - Event Router Configuration

    /// Set the event router for processing captured events
    func setEventRouter(_ router: EventRouter?, kanataManager: KanataManager? = nil) {
        eventRouter = router
        self.kanataManager = kanataManager
        AppLogger.shared.log("📋 [KeyboardCapture] Event router \(router != nil ? "enabled" : "disabled")")
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

    // Emergency stop sequence detection
    private var emergencyEventTap: CFMachPort?
    private var emergencyRunLoopSource: CFRunLoopSource?
    private var emergencyCallback: (() -> Void)?
    private var isMonitoringEmergency = false
    private var pressedKeys: Set<Int64> = []

    func startCapture(callback: @escaping (String) -> Void) async {
        guard !isCapturing else { return }

        captureCallback = callback
        isCapturing = true
        isContinuous = false

        // Only start capture if we already have permissions
        // Don't prompt for permissions - let the wizard handle that
        if !(await checkAccessibilityPermissionsSilently()) {
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

        setupEventTap()
    }

    func startContinuousCapture(callback: @escaping (String) -> Void) async {
        guard !isCapturing else { return }

        captureCallback = callback
        isCapturing = true
        isContinuous = true

        // Only start capture if we already have permissions
        // Don't prompt for permissions - let the wizard handle that
        if !(await checkAccessibilityPermissionsSilently()) {
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
    func startSequenceCapture(mode: CaptureMode, callback: @escaping (KeySequence) -> Void) async {
        guard !isCapturing else { return }

        captureMode = mode
        sequenceCallback = callback
        capturedKeys = []
        lastKeyTime = nil
        isCapturing = true
        isContinuous = (mode == .sequence)

        // Check permissions first
        if !(await checkAccessibilityPermissionsSilently()) {
            isCapturing = false
            sequenceCallback = nil
            let errorSequence = KeySequence(keys: [], captureMode: mode)
            callback(errorSequence)

            if !TestEnvironment.isRunningTests {
                // Trigger permission wizard
                NotificationCenter.default.post(
                    name: NSNotification.Name("KeyboardCapturePermissionNeeded"),
                    object: nil,
                    userInfo: ["reason": "Accessibility permission required for \(mode.displayName.lowercased()) capture"]
                )

                AppLogger.shared.log("⚠️ [KeyboardCapture] Accessibility permission missing for \(mode) capture")
            } else {
                AppLogger.shared.log(
                    "🧪 [KeyboardCapture] Skipping wizard trigger (sequence) in test environment")
            }
            return
        }

        AppLogger.shared.log("🎹 [KeyboardCapture] Starting \(mode) capture")
        setupEventTap()
    }

    func stopCapture() {
        guard isCapturing else { return }

        isCapturing = false
        isContinuous = false
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

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    private func setupEventTap() {
        // Note: We allow event tap creation even when Kanata is running
        // Users haven't reported conflicts, and it's useful to record keys while testing
        if let kanataManager, kanataManager.isRunning {
            AppLogger.shared.log("⚠️ [KeyboardCapture] WARNING: Creating CGEvent tap while Kanata is running - potential for conflicts")
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        AppLogger.shared.log("🎯 [KeyboardCapture] Creating CGEvent tap with parameters:")
        AppLogger.shared.log("🎯 [KeyboardCapture] - Location: cgSessionEventTap")
        AppLogger.shared.log("🎯 [KeyboardCapture] - Place: headInsertEventTap") 
        AppLogger.shared.log("🎯 [KeyboardCapture] - Options: defaultTap (intercept mode)")
        AppLogger.shared.log("🎯 [KeyboardCapture] - Event mask: \(eventMask) (keyDown events)")
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // Recording mode: intercept and suppress events
            eventsOfInterest: CGEventMask(eventMask),
            callback: { tapProxy, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { 
                    AppLogger.shared.log("⚠️ [KeyboardCapture] Event tap callback missing refcon - unexpected")
                    return Unmanaged.passRetained(event) 
                }

                let capture = Unmanaged<KeyboardCapture>.fromOpaque(refcon).takeUnretainedValue()
                
                // Log that we're receiving events (this confirms tap is working)
                AppLogger.shared.log("📥 [KeyboardCapture] Event tap intercepted keyDown event")

                // Process through event router if enabled
                if capture.useEventRouter, let router = capture.eventRouter {
                    AppLogger.shared.log("🔄 [KeyboardCapture] Processing event through router")
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
                    // Recording mode: suppress the event (prevent system beeps/errors)
                    AppLogger.shared.log("🔇 [KeyboardCapture] Event suppressed (recording mode)")
                    return nil
                } else {
                    // Legacy behavior - process directly
                    AppLogger.shared.log("🔄 [KeyboardCapture] Processing event directly (legacy mode)")
                    capture.handleKeyEvent(event)
                    // Recording mode: suppress the event (prevent system beeps/errors)
                    AppLogger.shared.log("🔇 [KeyboardCapture] Event suppressed (recording mode)")
                    return nil
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            AppLogger.shared.log("❌ [KeyboardCapture] Failed to create event tap")
            AppLogger.shared.log("❌ [KeyboardCapture] This usually indicates missing Input Monitoring permission")
            AppLogger.shared.log("❌ [KeyboardCapture] Please grant both Accessibility AND Input Monitoring permissions")
            isCapturing = false
            captureCallback?("⚠️ Grant Input Monitoring permission in System Settings")
            sequenceCallback?(KeySequence(keys: [], captureMode: .single))
            return
        }
        
        AppLogger.shared.log("✅ [KeyboardCapture] CGEvent tap object created successfully")

        // Add tap to run loop and enable
        AppLogger.shared.log("🔗 [KeyboardCapture] Adding event tap to run loop...")
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource else {
            AppLogger.shared.log("❌ [KeyboardCapture] Failed to create run loop source for event tap")
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            isCapturing = false
            captureCallback?("⚠️ Failed to setup event monitoring")
            sequenceCallback?(KeySequence(keys: [], captureMode: .single))
            return
        }
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        AppLogger.shared.log("✅ [KeyboardCapture] Event tap added to run loop")
        
        // Enable the tap
        CGEvent.tapEnable(tap: eventTap, enable: true)
        AppLogger.shared.log("✅ [KeyboardCapture] Event tap enabled")
        
        // Validate that the tap is actually working
        validateEventTap()
    }
    
    /// Validate that the event tap is actually functional
    private func validateEventTap() {
        guard let eventTap else {
            AppLogger.shared.log("❌ [KeyboardCapture] Cannot validate - no event tap exists")
            return
        }
        
        // Check if the tap is enabled
        let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        AppLogger.shared.log("🔍 [KeyboardCapture] Event tap enabled status: \(isEnabled)")
        
        if !isEnabled {
            AppLogger.shared.log("⚠️ [KeyboardCapture] Event tap was disabled - may be blocked by macOS security")
            AppLogger.shared.log("⚠️ [KeyboardCapture] This often indicates missing Input Monitoring permission")
            
            // Try to re-enable it
            CGEvent.tapEnable(tap: eventTap, enable: true)
            let nowEnabled = CGEvent.tapIsEnabled(tap: eventTap)
            AppLogger.shared.log("🔄 [KeyboardCapture] Re-enable attempt result: \(nowEnabled)")
        }
        
        // Set up a timeout to check if we receive any events within reasonable time
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.checkEventTapActivity()
        }
    }
    
    /// Check if the event tap has received any events (called after timeout)
    private func checkEventTapActivity() {
        // This will be called after 5 seconds - if we haven't received any keyDown events,
        // we can provide helpful diagnostic information
        AppLogger.shared.log("🔍 [KeyboardCapture] Event tap activity check (after 5 second timeout)")
        
        guard let eventTap else { 
            AppLogger.shared.log("❌ [KeyboardCapture] No event tap exists during activity check")
            return 
        }
        
        let isStillEnabled = CGEvent.tapIsEnabled(tap: eventTap)
        AppLogger.shared.log("🔍 [KeyboardCapture] Event tap still enabled: \(isStillEnabled)")
        
        if isStillEnabled {
            AppLogger.shared.log("ℹ️ [KeyboardCapture] Event tap is enabled but may not be receiving events - check if user is actually pressing keys during recording")
        }
        
        if !isStillEnabled {
            AppLogger.shared.log("⚠️ [KeyboardCapture] Event tap was disabled during recording - likely permission issue")
            
            DispatchQueue.main.async {
                // Update UI to show the issue
                if self.captureCallback != nil {
                    self.captureCallback?("⚠️ Event monitoring was disabled - check permissions")
                }
                if self.sequenceCallback != nil {
                    self.sequenceCallback?(KeySequence(keys: [], captureMode: self.captureMode))
                }
                self.stopCapture()
            }
        }
    }

    private func handleKeyEvent(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let keyName = keyCodeToString(keyCode)
        let modifiers = ModifierSet(cgEventFlags: event.flags)
        let now = Date()
        
        AppLogger.shared.log("🎹 [KeyboardCapture] Processing key event: \(keyName) (code: \(keyCode))")

        // Create KeyPress
        let keyPress = KeyPress(
            baseKey: keyName,
            modifiers: modifiers,
            timestamp: now,
            keyCode: keyCode
        )

        DispatchQueue.main.async {
            AppLogger.shared.log("🎯 [KeyboardCapture] Dispatching to main thread for processing")
            
            // Handle legacy callback if set (for backward compatibility)
            if self.sequenceCallback == nil, let legacyCallback = self.captureCallback {
                AppLogger.shared.log("🔄 [KeyboardCapture] Using legacy callback mode")
                legacyCallback(keyName)

                if !self.isContinuous {
                    AppLogger.shared.log("🛑 [KeyboardCapture] Single capture mode - stopping after key")
                    self.stopCapture()
                } else {
                    AppLogger.shared.log("🔄 [KeyboardCapture] Continuous mode - resetting pause timer")
                    self.resetPauseTimer()
                }
                return
            }

            // Handle new sequence capture
            AppLogger.shared.log("🔄 [KeyboardCapture] Using sequence capture mode")
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

            // Reset chord timer
            chordTimer?.invalidate()
            chordTimer = Timer.scheduledTimer(withTimeInterval: chordWindow, repeats: false) { _ in
                Task { @MainActor in self.completeChord() }
            }

        case .sequence:
            // Sequence capture - accumulate keys
            capturedKeys.append(keyPress)
            lastKeyTime = now

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
        pauseTimer = Timer.scheduledTimer(withTimeInterval: pauseDuration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
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

    // Check permissions without prompting
    func checkAccessibilityPermissionsSilently() async -> Bool {
        let snapshot = await PermissionOracle.shared.currentSnapshot()
        return snapshot.keyPath.accessibility.isReady
    }
    
    // Legacy synchronous version for compatibility (avoid using from @MainActor contexts)
    @available(*, deprecated, message: "Use async version to avoid blocking main thread")
    func checkAccessibilityPermissionsSilentlySync() -> Bool {
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let snapshot = await PermissionOracle.shared.currentSnapshot()
            result = snapshot.keyPath.accessibility.isReady
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    // Public method to explicitly request permissions (for use in wizard)
    func requestPermissionsExplicitly() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Emergency Stop Sequence Detection

    func startEmergencyMonitoring(callback: @escaping () -> Void) async {
        guard !isMonitoringEmergency else { return }

        // Safety check: avoid CGEvent tap conflicts when Kanata is running
        // Per ADR-006, emergency monitoring should also respect the single tap rule
        if let kanataManager, kanataManager.isRunning {
            AppLogger.shared.log("⚠️ [KeyboardCapture] Emergency monitoring disabled - Kanata is running (ADR-006 compliance)")
            return
        }

        emergencyCallback = callback
        isMonitoringEmergency = true

        // Only start monitoring if we already have permissions
        // Don't prompt for permissions - let the wizard handle that
        if !(await checkAccessibilityPermissionsSilently()) {
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
            print("Failed to create emergency event tap")
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
