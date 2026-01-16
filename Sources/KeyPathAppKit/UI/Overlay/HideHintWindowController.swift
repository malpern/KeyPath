import AppKit
import KeyPathCore
import SwiftUI

/// A separate floating window that shows the "Hide — ⌘⌥K" hint above the keyboard overlay.
/// Completely decoupled from the keyboard layout to avoid affecting it.
/// The key chips respond to actual key presses for visual feedback.
@MainActor
final class HideHintWindowController {
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?
    private let keyState = HideShortcutKeyState()

    // Event monitors for tracking key presses
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?

    /// Show the hint bubble above the given parent window
    func show(above parentWindow: NSWindow) {
        // Don't show if already visible
        guard window == nil else { return }

        // Create the hint bubble view with key state
        var isVisible = true
        let hintView = HideHintBubble(
            isVisible: Binding(
                get: { isVisible },
                set: { [weak self] newValue in
                    isVisible = newValue
                    if !newValue {
                        self?.dismiss()
                    }
                }
            ),
            keyState: keyState
        )

        let hostingView = NSHostingView(rootView: hintView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 36)

        // Size to fit content
        let fittingSize = hostingView.fittingSize
        hostingView.frame.size = fittingSize

        // Create borderless, transparent window
        let hintWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hintWindow.isOpaque = false
        hintWindow.backgroundColor = .clear
        hintWindow.level = .floating
        hintWindow.hasShadow = false
        hintWindow.ignoresMouseEvents = true // Click-through
        hintWindow.contentView = hostingView

        // Position above the parent window, aligned to the right
        let parentFrame = parentWindow.frame
        let hintX = parentFrame.maxX - fittingSize.width - 14 // Align with hide button
        let hintY = parentFrame.maxY + 4 // Just above the parent
        hintWindow.setFrameOrigin(NSPoint(x: hintX, y: hintY))

        // Make it a child of the parent window so it moves together
        parentWindow.addChildWindow(hintWindow, ordered: .above)

        hintWindow.orderFront(nil)
        window = hintWindow

        // Start key event monitoring
        startKeyMonitoring()

        // Start dismiss timer
        startDismissTimer()

        AppLogger.shared.log("🔔 [HideHintWindow] Showing hint bubble above overlay")
    }

    /// Dismiss the hint bubble
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        stopKeyMonitoring()
        keyState.reset()

        guard let window else { return }

        // Fade out animation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.window?.parent?.removeChildWindow(window)
            self?.window?.orderOut(nil)
            self?.window = nil
            AppLogger.shared.log("🔔 [HideHintWindow] Hint bubble dismissed")
        }
    }

    private func startDismissTimer() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// Update position if parent window moves
    func updatePosition(parentWindow: NSWindow) {
        guard let window else { return }
        let parentFrame = parentWindow.frame
        let hintX = parentFrame.maxX - window.frame.width - 14
        let hintY = parentFrame.maxY + 4
        window.setFrameOrigin(NSPoint(x: hintX, y: hintY))
    }

    /// Check if hint is currently visible
    var isVisible: Bool {
        window != nil
    }

    // MARK: - Key Event Monitoring

    private func startKeyMonitoring() {
        // Monitor modifier flags (Command, Option)
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        // Monitor key down for K key
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
        }

        // Monitor key up for K key
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyUp(event)
            }
        }
    }

    private func stopKeyMonitoring() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags

        // Check Command key
        keyState.commandPressed = flags.contains(.command)

        // Check Option key
        keyState.optionPressed = flags.contains(.option)

        // Check if all keys are pressed
        keyState.checkAllPressed()
    }

    private func handleKeyDown(_ event: NSEvent) {
        // K key has keyCode 40
        if event.keyCode == 40 {
            keyState.kPressed = true
            keyState.checkAllPressed()
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        // K key has keyCode 40
        if event.keyCode == 40 {
            keyState.kPressed = false
        }
    }
}
