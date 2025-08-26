import Carbon
import Foundation
import SwiftUI

// Import the event processing infrastructure
#if canImport(KeyPath)
    // This is to handle potential circular dependencies during build
#endif

public class KeyboardCapture: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var captureCallback: ((String) -> Void)?
    private var isCapturing = false
    private var isContinuous = false
    private var pauseTimer: Timer?
    private let pauseDuration: TimeInterval = 2.0 // 2 seconds pause to auto-stop

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

    func startCapture(callback: @escaping (String) -> Void) {
        guard !isCapturing else { return }

        captureCallback = callback
        isCapturing = true
        isContinuous = false

        // Only start capture if we already have permissions
        // Don't prompt for permissions - let the wizard handle that
        if !hasAccessibilityPermissions() {
            // Notify that we need permissions - this should trigger the wizard
            isCapturing = false
            captureCallback = nil
            callback("⚠️ Accessibility permission required")

            // Trigger the wizard to help user fix permissions
            NotificationCenter.default.post(
                name: NSNotification.Name("KeyboardCapturePermissionNeeded"),
                object: nil,
                userInfo: ["reason": "Accessibility permission required for keyboard capture"]
            )

            AppLogger.shared.log(
                "⚠️ [KeyboardCapture] Accessibility permission missing - triggering wizard")
            return
        }

        setupEventTap()
    }

    func startContinuousCapture(callback: @escaping (String) -> Void) {
        guard !isCapturing else { return }

        captureCallback = callback
        isCapturing = true
        isContinuous = true

        // Only start capture if we already have permissions
        // Don't prompt for permissions - let the wizard handle that
        if !hasAccessibilityPermissions() {
            // Notify that we need permissions - this should trigger the wizard
            isCapturing = false
            isContinuous = false
            captureCallback = nil
            callback("⚠️ Accessibility permission required")

            // Trigger the wizard to help user fix permissions
            NotificationCenter.default.post(
                name: NSNotification.Name("KeyboardCapturePermissionNeeded"),
                object: nil,
                userInfo: ["reason": "Accessibility permission required for continuous keyboard capture"]
            )

            AppLogger.shared.log(
                "⚠️ [KeyboardCapture] Accessibility permission missing for continuous capture - triggering wizard"
            )
            return
        }

        setupEventTap()
    }

    func stopCapture() {
        guard isCapturing else { return }

        isCapturing = false
        isContinuous = false
        captureCallback = nil

        // Cancel pause timer
        pauseTimer?.invalidate()
        pauseTimer = nil

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
        // Safety check: avoid CGEvent tap conflicts when Kanata is running
        // Per ADR-006, we should not create competing event taps
        if let kanataManager, kanataManager.isRunning {
            AppLogger.shared.log("⚠️ [KeyboardCapture] Skipping CGEvent tap setup - Kanata is running (ADR-006 compliance)")
            // Fall back to disabling capture to avoid conflicts
            isCapturing = false
            isContinuous = false
            captureCallback = nil

            DispatchQueue.main.async {
                self.captureCallback?("⚠️ Cannot capture while Kanata is running")
            }
            return
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // Recording mode: intercept and suppress events
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
                    // Recording mode: suppress the event (prevent system beeps/errors)
                    return nil
                } else {
                    // Legacy behavior - process directly
                    capture.handleKeyEvent(event)
                    // Recording mode: suppress the event (prevent system beeps/errors)
                    return nil
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            print("Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleKeyEvent(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let keyName = keyCodeToString(keyCode)

        DispatchQueue.main.async {
            self.captureCallback?(keyName)

            if !self.isContinuous {
                // Single key capture - stop immediately
                self.stopCapture()
            } else {
                // Continuous capture - reset pause timer
                self.resetPauseTimer()
            }
        }
    }

    private func resetPauseTimer() {
        // Cancel existing timer
        pauseTimer?.invalidate()

        // Start new timer for auto-stop after pause
        pauseTimer = Timer.scheduledTimer(withTimeInterval: pauseDuration, repeats: false) {
            [weak self] _ in
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

    private func hasAccessibilityPermissions() -> Bool {
        AXIsProcessTrusted()
    }

    private func requestAccessibilityPermissions() {
        let options: [CFString: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // Check permissions without prompting
    func checkAccessibilityPermissionsSilently() -> Bool {
        AXIsProcessTrusted()
    }

    // Public method to explicitly request permissions (for use in wizard)
    func requestPermissionsExplicitly() {
        requestAccessibilityPermissions()
    }

    // MARK: - Emergency Stop Sequence Detection

    func startEmergencyMonitoring(callback: @escaping () -> Void) {
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
        if !hasAccessibilityPermissions() {
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
