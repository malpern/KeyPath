import Foundation
import Carbon
import SwiftUI

class KeyboardCapture: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var captureCallback: ((String) -> Void)?
    private var isCapturing = false
    private var isContinuous = false
    private var pauseTimer: Timer?
    private let pauseDuration: TimeInterval = 2.0 // 2 seconds pause to auto-stop
    
    func startCapture(callback: @escaping (String) -> Void) {
        guard !isCapturing else { return }
        
        captureCallback = callback
        isCapturing = true
        isContinuous = false
        
        // Request accessibility permissions if needed
        if !hasAccessibilityPermissions() {
            requestAccessibilityPermissions()
            return
        }
        
        setupEventTap()
    }
    
    func startContinuousCapture(callback: @escaping (String) -> Void) {
        guard !isCapturing else { return }
        
        captureCallback = callback
        isCapturing = true
        isContinuous = true
        
        // Request accessibility permissions if needed
        if !hasAccessibilityPermissions() {
            requestAccessibilityPermissions()
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
        
        if let eventTap = eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        
        if let runLoopSource = runLoopSource {
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
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                
                let capture = Unmanaged<KeyboardCapture>.fromOpaque(refcon).takeUnretainedValue()
                capture.handleKeyEvent(event)
                
                // Return nil to suppress the event
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
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
    
    private func hasAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    private func requestAccessibilityPermissions() {
        let options: [CFString: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}