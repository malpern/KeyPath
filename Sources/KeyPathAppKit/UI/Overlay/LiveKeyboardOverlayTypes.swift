import AppKit
import Combine
import KeyPathCore
import SwiftUI

// MARK: - Health Indicator State

/// State for the system health indicator shown in the overlay header
enum HealthIndicatorState: Equatable {
    case checking
    case healthy
    case unhealthy(issueCount: Int)
    case dismissed
}

@MainActor
final class LiveKeyboardOverlayUIState: ObservableObject {
    @Published var isInspectorOpen = false
    @Published var inspectorReveal: CGFloat = 0
    @Published var isInspectorAnimating = false
    @Published var isInspectorClosing = false
    @Published var desiredContentHeight: CGFloat = 0
    @Published var desiredContentWidth: CGFloat = 0
    @Published var keyboardAspectRatio: CGFloat = PhysicalLayout.macBookUS.totalWidth / PhysicalLayout.macBookUS.totalHeight

    // Health indicator state for startup validation display
    @Published var healthIndicatorState: HealthIndicatorState = .dismissed

    /// Brief highlight of the drawer button when toggled via hotkey
    @Published var drawerButtonHighlighted = false

    /// Whether the hide hint bubble is currently showing (affects window height)
    @Published var showingHintBubble = false

    /// Height of the hint bubble area when shown
    static let hintBubbleHeight: CGFloat = 40
}

enum InspectorPanelLayout {
    static func expandedFrame(
        baseFrame: NSRect,
        inspectorWidth: CGFloat,
        maxVisibleX: CGFloat?
    ) -> NSRect {
        var expanded = baseFrame
        expanded.size.width += inspectorWidth

        if let maxVisibleX {
            let overflow = expanded.maxX - maxVisibleX
            if overflow > 0 {
                expanded.origin.x -= overflow
            }
        }

        return expanded
    }

    static func collapsedFrame(expandedFrame: NSRect, inspectorWidth: CGFloat) -> NSRect {
        var collapsed = expandedFrame
        collapsed.size.width = max(0, expandedFrame.width - inspectorWidth)
        return collapsed
    }
}

// MARK: - Overlay Window (allows partial off-screen positioning)

final class OverlayWindow: NSWindow {
    /// Keep at least this many points visible inside the screen's visibleFrame so the window is recoverable.
    private let minVisible: CGFloat = 30

    /// Prevent the window from becoming key window (so it doesn't steal keyboard focus from other apps)
    override var canBecomeKey: Bool { false }

    /// Prevent the window from becoming main window
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen else { return frameRect }

        let visible = screen.visibleFrame
        var rect = frameRect

        // Horizontal: ensure at least `minVisible` points remain on-screen
        if rect.maxX < visible.minX + minVisible {
            rect.origin.x = visible.minX + minVisible - rect.width
        } else if rect.minX > visible.maxX - minVisible {
            rect.origin.x = visible.maxX - minVisible
        }

        // Vertical: ensure at least `minVisible` points remain on-screen
        if rect.maxY < visible.minY + minVisible {
            rect.origin.y = visible.minY + minVisible - rect.height
        } else if rect.minY > visible.maxY - minVisible {
            rect.origin.y = visible.maxY - minVisible
        }

        return rect
    }
}

@MainActor
final class OneShotLayerOverrideState {
    private(set) var currentLayer: String?
    private var overrideTask: Task<Void, Never>?
    private var overrideToken = UUID()
    private let timeoutNanoseconds: UInt64
    private let sleep: @Sendable (UInt64) async -> Void

    init(
        timeoutNanoseconds: UInt64,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanos in
            try? await Task.sleep(nanoseconds: nanos)
        }
    ) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.sleep = sleep
    }

    func activate(_ layer: String) {
        currentLayer = layer
        scheduleTimeout()
    }

    func clear() {
        currentLayer = nil
        cancelTimeout()
    }

    func clearOnKeyPress(_ key: String, modifierKeys: Set<String>) -> String? {
        guard let layer = currentLayer,
              !modifierKeys.contains(key.lowercased())
        else {
            return nil
        }
        clear()
        return layer
    }

    func shouldIgnoreKanataUpdate(normalizedLayer: String) -> Bool {
        guard let layer = currentLayer else { return false }
        return normalizedLayer != layer
    }

    private func scheduleTimeout() {
        cancelTimeout()
        let token = UUID()
        overrideToken = token
        overrideTask = Task { @MainActor in
            await sleep(timeoutNanoseconds)
            guard overrideToken == token else { return }
            if let layer = currentLayer {
                AppLogger.shared.debug(
                    "🧭 [OverlayController] One-shot override '\(layer)' expired"
                )
                currentLayer = nil
            }
        }
    }

    private func cancelTimeout() {
        overrideTask?.cancel()
        overrideTask = nil
    }
}

// MARK: - Notification Integration

extension Notification.Name {
    /// Posted when the live keyboard overlay should be toggled
    static let toggleLiveKeyboardOverlay = Notification.Name("KeyPath.ToggleLiveKeyboardOverlay")
    /// Posted when the Kanata layer changes (userInfo["layerName"] = String)
    static let kanataLayerChanged = Notification.Name("KeyPath.KanataLayerChanged")
    /// Posted when the Kanata config changes (rules saved, etc.)
    static let kanataConfigChanged = Notification.Name("KeyPath.KanataConfigChanged")
    /// Posted when a TCP message is received from Kanata (heartbeat for connection state)
    static let kanataTcpHeartbeat = Notification.Name("KeyPath.KanataTcpHeartbeat")
    /// Posted when a physical key is pressed/released (userInfo["key"] = String, ["action"] = "press"/"release")
    static let kanataKeyInput = Notification.Name("KeyPath.KanataKeyInput")
    /// Posted when a tap-hold key transitions to hold state (userInfo["key"] = String, ["action"] = String)
    static let kanataHoldActivated = Notification.Name("KeyPath.KanataHoldActivated")
    /// Posted when a tap-hold key triggers its tap action (userInfo["key"] = String, ["action"] = String)
    static let kanataTapActivated = Notification.Name("KeyPath.KanataTapActivated")
    /// Posted when a one-shot modifier is activated (userInfo["key"] = String, ["modifiers"] = String)
    static let kanataOneShotActivated = Notification.Name("KeyPath.KanataOneShotActivated")
    /// Posted when a chord resolves (userInfo["keys"] = String, ["action"] = String)
    static let kanataChordResolved = Notification.Name("KeyPath.KanataChordResolved")
    /// Posted when a tap-dance resolves (userInfo["key"] = String, ["tapCount"] = Int, ["action"] = String)
    static let kanataTapDanceResolved = Notification.Name("KeyPath.KanataTapDanceResolved")
    /// Posted when a generic push-msg is received (userInfo["message"] = String) - e.g., "icon:arrow-left", "emphasis:h,j,k,l"
    static let kanataMessagePush = Notification.Name("KeyPath.KanataMessagePush")
}
