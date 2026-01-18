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
    private var fadeInTask: Task<Void, Never>?
    private let keyState = HideShortcutKeyState()

    // Event monitors for tracking key presses
    // We need both global (when app not focused) and local (when app focused) monitors
    private var globalFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?

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

        // Start invisible, then fade in
        hintWindow.alphaValue = 0
        hintWindow.orderFront(nil)
        window = hintWindow

        // Start key event monitoring
        startKeyMonitoring()

        // Fade in immediately, then start dismiss timer
        fadeIn()

        AppLogger.shared.log("🔔 [HideHintWindow] Showing hint bubble above overlay")
    }

    /// Dismiss the hint bubble
    func dismiss() {
        fadeInTask?.cancel()
        fadeInTask = nil
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
            MainActor.assumeIsolated {
                self?.window?.parent?.removeChildWindow(window)
                self?.window?.orderOut(nil)
                self?.window = nil
                AppLogger.shared.log("🔔 [HideHintWindow] Hint bubble dismissed")
            }
        }
    }

    private func fadeIn() {
        guard let window else { return }

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1.0
        } completionHandler: { [weak self] in
            AppLogger.shared.log("🔔 [HideHintWindow] Hint bubble faded in")
            // Start the 10 second dismiss timer after fade completes
            Task { @MainActor in
                self?.startDismissTimer()
            }
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
        // Global monitors for when app is NOT focused
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
        }

        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyUp(event)
            }
        }

        // Local monitors for when app IS focused
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event // Don't consume the event
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyDown(event)
            }
            return event // Don't consume the event
        }

        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyUp(event)
            }
            return event // Don't consume the event
        }
    }

    private func stopKeyMonitoring() {
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        if let monitor = globalKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyDownMonitor = nil
        }
        if let monitor = globalKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyUpMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyDownMonitor = nil
        }
        if let monitor = localKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyUpMonitor = nil
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        keyState.commandPressed = flags.contains(.command)
        keyState.optionPressed = flags.contains(.option)
    }

    private func handleKeyDown(_ event: NSEvent) {
        // K key has keyCode 40
        if event.keyCode == 40 {
            keyState.kPressed = true
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        // K key has keyCode 40
        if event.keyCode == 40 {
            keyState.kPressed = false
        }
    }
}
