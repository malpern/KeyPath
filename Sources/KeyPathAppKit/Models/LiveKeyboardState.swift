import Foundation
import SwiftUI

// MARK: - Live Keyboard State

/// Tracks the live state of the keyboard from Kanata's KeyInput events.
/// Used by the overlay UI to show which keys are currently pressed.
@MainActor
@Observable
final class LiveKeyboardState {
    // MARK: - State

    /// Set of Kanata key names that are currently pressed
    private(set) var pressedKeys: Set<String> = []

    /// Current layer name (from LayerChange events)
    private(set) var currentLayer: String = "base"

    /// Whether we're receiving events (connected to Kanata)
    private(set) var isConnected: Bool = false

    /// Last event timestamp (for staleness detection)
    private(set) var lastEventTime: Date?

    // MARK: - Event Handling

    /// Handle a key input event from Kanata
    func handleKeyInput(_ event: LiveKeyEvent) {
        lastEventTime = Date()
        isConnected = true

        switch event.action {
        case .press:
            pressedKeys.insert(event.key)
        case .release:
            pressedKeys.remove(event.key)
        case .repeat:
            // Repeat events don't change state, but confirm key is still pressed
            pressedKeys.insert(event.key)
        }
    }

    /// Handle a layer change event
    func handleLayerChange(_ layer: String) {
        lastEventTime = Date()
        isConnected = true
        currentLayer = layer
    }

    /// Mark as disconnected and clear transient state
    func handleDisconnect() {
        isConnected = false
        pressedKeys.removeAll()
        // Keep currentLayer as-is until reconnect
    }

    /// Clear all state (for testing or reset)
    func reset() {
        pressedKeys.removeAll()
        currentLayer = "base"
        isConnected = false
        lastEventTime = nil
    }

    // MARK: - Query Methods

    /// Check if a specific key is currently pressed
    func isKeyPressed(_ kanataKey: String) -> Bool {
        pressedKeys.contains(kanataKey)
    }

    /// Check if any modifier is held (for UI highlighting)
    var hasActiveModifier: Bool {
        let modifiers = ["leftshift", "rightshift", "leftctrl", "rightctrl", "leftalt", "rightalt", "leftmeta", "rightmeta"]
        return pressedKeys.contains { modifiers.contains($0) }
    }

    /// Get all currently pressed modifier keys
    var activeModifiers: Set<String> {
        let modifiers = ["leftshift", "rightshift", "leftctrl", "rightctrl", "leftalt", "rightalt", "leftmeta", "rightmeta"]
        return pressedKeys.filter { modifiers.contains($0) }
    }
}

// MARK: - Testing Support

extension LiveKeyboardState {
    /// Create with preset state for testing/previews
    static func preview(pressedKeys: Set<String> = [], layer: String = "base") -> LiveKeyboardState {
        let state = LiveKeyboardState()
        state.pressedKeys = pressedKeys
        state.currentLayer = layer
        state.isConnected = true
        state.lastEventTime = Date()
        return state
    }
}
