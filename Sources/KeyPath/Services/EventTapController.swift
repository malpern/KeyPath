import ApplicationServices
import Foundation
import KeyPathCore

/// Controller for CGEvent/IOHID concerns. Provides a narrow surface for
/// installing a passive event tap and delegating emergency monitoring via
/// KeyboardCapture.
@MainActor
final class EventTapController: EventTapping {
    private var currentTap: TapHandle?
    private var keyboardCapture: KeyboardCapture?

    init(keyboardCapture: KeyboardCapture? = nil) {
        self.keyboardCapture = keyboardCapture
    }

    var isInstalled: Bool {
        currentTap != nil
    }

    /// Install a listen-only CGEvent tap for keyDown events.
    func install() throws -> TapHandle {
        guard currentTap == nil else { throw TapError.alreadyInstalled }

        // Avoid creating taps in test environments
        if TestEnvironment.isRunningTests {
            throw TapError.installationFailed(reason: "Test environment - event taps disabled")
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)
        guard let machPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, event, _ in
                // Always pass event through
                Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            throw TapError.installationFailed(reason: "CGEvent.tapCreate returned nil")
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, machPort, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: machPort, enable: true)

        let handle = TapHandle(machPort: machPort, runLoopSource: source)
        currentTap = handle
        return handle
    }

    func uninstall() {
        guard let handle = currentTap else { return }
        if let source = handle.runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CFMachPortInvalidate(handle.machPort)
        currentTap = nil
    }

    // MARK: - Emergency Monitoring Convenience

    func startEmergencyMonitoring(_ callback: @escaping () -> Void) {
        ensureKeyboardCapture()
        keyboardCapture?.startEmergencyMonitoring(callback: callback)
    }

    func stopEmergencyMonitoring() {
        keyboardCapture?.stopEmergencyMonitoring()
    }

    private func ensureKeyboardCapture() {
        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
        }
    }
}

enum TapError: Error {
    case alreadyInstalled
    case installationFailed(reason: String)
}


