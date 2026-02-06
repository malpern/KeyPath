import Foundation
import KeyPathCore

@MainActor
extension KeyboardCapture {
    // MARK: - TCP-Based Capture (when Kanata is running)

    /// Set up TCP-based key capture by subscribing to Kanata KeyInput notifications.
    /// This avoids CGEvent tap conflicts when Kanata is running.
    func setupTcpCapture() {
        isTcpCaptureMode = true

        tcpKeyInputObserver = NotificationCenter.default.addObserver(
            forName: .kanataKeyInput,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // Extract values from notification before crossing actor boundary
            guard let userInfo = notification.userInfo,
                  let keyName = userInfo["key"] as? String,
                  let action = userInfo["action"] as? String,
                  action == "press"
            else { return }
            Task { @MainActor in
                // Check isCapturing on MainActor to avoid concurrency warning
                guard self.isCapturing else { return }
                self.handleTcpKeyInputValues(keyName: keyName, action: action)
            }
        }

        AppLogger.shared.info("✅ [KeyboardCapture] TCP-based capture started (subscribed to .kanataKeyInput)")
    }

    /// Handle extracted TCP KeyInput values and convert to a KeyPress
    func handleTcpKeyInputValues(keyName: String, action: String) {
        guard isCapturing else { return }

        anyEventSeen = true
        noKeyBreadcrumbTimer?.invalidate()
        noKeyBreadcrumbTimer = nil

        AppLogger.shared.log("🎹 [KeyboardCapture] TCP keyInput: \(keyName) action=\(action)")

        // Convert TCP key name to KeyPress
        let keyPress = KeyPress(
            baseKey: keyName,
            modifiers: [], // TCP events don't include modifier state, but key name includes modifier keys
            timestamp: Date(),
            keyCode: tcpKeyNameToKeyCode(keyName)
        )

        // Notify activity observer
        activityObserver?.didReceiveKeyEvent(keyPress)

        // De-dup identical events
        if let last = lastCapturedKey, let lastAt = lastCaptureAt {
            if last.baseKey == keyPress.baseKey,
               Date().timeIntervalSince(lastAt) <= dedupWindow {
                AppLogger.shared.log("🎹 [KeyboardCapture] Deduped duplicate TCP key: \(keyName)")
                return
            }
        }
        lastCapturedKey = keyPress
        lastCaptureAt = Date()

        // Handle legacy callback if set
        if sequenceCallback == nil, let legacyCallback = captureCallback {
            legacyCallback(keyName)
            if !isContinuous {
                stopCapture()
            } else {
                resetPauseTimer()
            }
            return
        }

        // Handle sequence capture
        processKeyPress(keyPress)
    }

    /// Convert a TCP key name to an approximate macOS key code
    /// Note: This is best-effort since TCP key names don't map 1:1 to macOS codes
    func tcpKeyNameToKeyCode(_ keyName: String) -> Int64 {
        // Common key name to keycode mapping (same as keyCodeToString but reversed)
        let keyMap: [String: Int64] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "ret": 36,
            "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
            ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "spc": 49,
            "space": 49, "`": 50, "bspc": 51, "delete": 51, "esc": 53, "escape": 53,
            "caps": 57, "capslock": 57, "lsft": 56, "rsft": 60, "lctl": 59, "rctl": 62,
            "lalt": 58, "ralt": 61, "lmet": 55, "rmet": 54, "lopt": 58, "ropt": 61
        ]

        return keyMap[keyName.lowercased()] ?? -1
    }
}
