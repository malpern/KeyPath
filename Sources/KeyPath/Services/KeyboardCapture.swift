import Carbon
import Foundation
import SwiftUI

class KeyboardCapture: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var captureCallback: ((String) -> Void)?
    private var isCapturing = false
    private var isContinuous = false
    private var pauseTimer: Timer?
    private let pauseDuration: TimeInterval = 2.0 // 2 seconds pause to auto-stop

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
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }

                let capture = Unmanaged<KeyboardCapture>.fromOpaque(refcon).takeUnretainedValue()
                capture.handleKeyEvent(event)

                // Return nil to suppress the event
                return nil
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
            50: "`", 51: "delete", 53: "escape", 58: "caps", 59: "caps",
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
            options: .defaultTap,
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
               pressedKeys.contains(escapeKey)
            {
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
