import AppKit
import Carbon
import Foundation
import KeyPathCore
import SwiftUI

/// ViewModel for keyboard visualization that tracks pressed keys
@MainActor
class KeyboardVisualizationViewModel: ObservableObject {
    @Published var pressedKeyCodes: Set<UInt16> = []
    @Published var layout: PhysicalLayout = .macBookUS

    // Event tap for listening to keyDown and keyUp events
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isCapturing = false

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
    }

    func stopCapturing() {
        guard isCapturing else { return }

        isCapturing = false
        pressedKeyCodes.removeAll()

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        AppLogger.shared.debug("⌨️ [KeyboardViz] Stopped capturing")
    }

    func isPressed(_ key: PhysicalKey) -> Bool {
        pressedKeyCodes.contains(key.keyCode)
    }

    // MARK: - Private Event Handling

    private func setupEventTap() {
        // Listen to both keyDown and keyUp events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

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

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        Task { @MainActor in
            switch type {
            case .keyDown:
                pressedKeyCodes.insert(keyCode)
                AppLogger.shared.debug("⌨️ [KeyboardViz] KeyDown: \(keyCode)")

            case .keyUp:
                pressedKeyCodes.remove(keyCode)
                AppLogger.shared.debug("⌨️ [KeyboardViz] KeyUp: \(keyCode)")

            default:
                break
            }
        }
    }
}
