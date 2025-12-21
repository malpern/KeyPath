import AppKit
import Foundation
import KeyPathCore
import SwiftUI

/// ViewModel for the keyboard simulator.
/// Manages queued key taps, simulation execution, and results display.
/// Tracks physical keyboard state for visual feedback.
@MainActor
final class SimulatorViewModel: ObservableObject {
    // MARK: - Input State

    /// Queued key taps waiting to be simulated
    @Published var queuedTaps: [SimulatorKeyTap] = []

    /// Default delay between taps in milliseconds
    @Published var defaultDelayMs: UInt64 = 200

    /// Default hold duration in milliseconds
    @Published var holdDelayMs: UInt64 = 400

    /// Currently pressed key codes (from physical keyboard)
    @Published var pressedKeyCodes: Set<UInt16> = []

    // MARK: - Output State

    /// Latest simulation result
    @Published var result: SimulationResult?

    /// Whether simulation is currently running
    @Published var isRunning = false

    /// Last error that occurred
    @Published var error: Error?

    // MARK: - Key Monitoring

    private var eventMonitor: Any?

    // MARK: - Dependencies

    private let service: SimulatorService

    /// Path to the user's config file
    var configPath: String {
        WizardSystemPaths.userConfigPath
    }

    init(service: SimulatorService = SimulatorService()) {
        self.service = service
    }

    // MARK: - Actions

    /// Add a key tap to the queue
    func tapKey(_ key: PhysicalKey) {
        let kanataKey = Self.keyCodeToKanataName(key.keyCode)
        let tap = SimulatorKeyTap(
            kanataKey: kanataKey,
            displayLabel: key.label,
            delayAfterMs: defaultDelayMs,
            isHold: false
        )
        queuedTaps.append(tap)
    }

    /// Add a key hold to the queue
    func holdKey(_ key: PhysicalKey) {
        let kanataKey = Self.keyCodeToKanataName(key.keyCode)
        let tap = SimulatorKeyTap(
            kanataKey: kanataKey,
            displayLabel: key.label,
            delayAfterMs: holdDelayMs,
            isHold: true
        )
        queuedTaps.append(tap)
    }

    /// Remove the last tap from the queue
    func removeLastTap() {
        _ = queuedTaps.popLast()
    }

    /// Clear all taps and results
    func clearAll() {
        queuedTaps.removeAll()
        result = nil
        error = nil
    }

    // MARK: - Physical Keyboard Monitoring

    /// Start monitoring physical keyboard events for visual feedback
    func startKeyMonitoring() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
            return event
        }
    }

    /// Stop monitoring physical keyboard events
    func stopKeyMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        pressedKeyCodes.removeAll()
    }

    /// Handle a physical keyboard event
    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = UInt16(event.keyCode)

        switch event.type {
        case .keyDown:
            pressedKeyCodes.insert(keyCode)
        case .keyUp:
            pressedKeyCodes.remove(keyCode)
        default:
            break
        }
    }

    /// Run the simulation with queued taps
    func runSimulation() async {
        guard !queuedTaps.isEmpty else { return }
        guard FeatureFlags.simulatorAndVirtualKeysEnabled else {
            error = SimulatorError.featureDisabled
            return
        }

        isRunning = true
        error = nil

        do {
            result = try await service.simulate(
                taps: queuedTaps,
                configPath: configPath
            )
        } catch {
            self.error = error
        }

        isRunning = false
    }

    // MARK: - Key Code Mapping

    /// Maps CGEvent key codes to Kanata key names.
    /// Based on PhysicalLayout.macBookUS key definitions.
    nonisolated static func keyCodeToKanataName(_ keyCode: UInt16) -> String {
        switch keyCode {
        // Row 3: Home row (ASDF...)
        case 0: "a"
        case 1: "s"
        case 2: "d"
        case 3: "f"
        case 4: "h"
        case 5: "g"
        // Row 4: Bottom row (ZXCV...)
        case 6: "z"
        case 7: "x"
        case 8: "c"
        case 9: "v"
        case 11: "b"
        // Row 2: Top row (QWERTY...)
        case 12: "q"
        case 13: "w"
        case 14: "e"
        case 15: "r"
        case 16: "y"
        case 17: "t"
        // Row 1: Number row
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "="
        case 25: "9"
        case 26: "7"
        case 27: "-"
        case 28: "8"
        case 29: "0"
        // More top row keys
        case 30: "]"
        case 31: "o"
        case 32: "u"
        case 33: "["
        case 34: "i"
        case 35: "p"
        // Home row continued
        case 36: "ret"
        case 37: "l"
        case 38: "j"
        case 39: "'"
        case 40: "k"
        case 41: ";"
        case 42: "\\"
        // Bottom row continued
        case 43: ","
        case 44: "/"
        case 45: "n"
        case 46: "m"
        case 47: "."
        // Special keys
        case 48: "tab"
        case 49: "spc"
        case 50: "grv" // Backtick/grave
        case 51: "bspc" // Backspace/Delete
        case 53: "esc"
        // Modifiers
        case 54: "rmet" // Right Command
        case 55: "lmet" // Left Command
        case 56: "lsft" // Left Shift
        case 57: "caps"
        case 58: "lalt" // Left Option
        case 59: "lctl" // Left Control
        case 60: "rsft" // Right Shift
        case 61: "ralt" // Right Option
        case 63: "fn"
        // Function keys
        case 96: "f5"
        case 97: "f6"
        case 98: "f7"
        case 99: "f3"
        case 100: "f8"
        case 101: "f9"
        case 103: "f11"
        case 109: "f10"
        case 111: "f12"
        case 118: "f4"
        case 120: "f2"
        case 122: "f1"
        // Arrow keys
        case 123: "left"
        case 124: "rght"
        case 125: "down"
        case 126: "up"
        default:
            "unknown-\(keyCode)"
        }
    }

    /// Get a display label for a Kanata key name
    nonisolated static func displayLabelForKanataKey(_ key: String) -> String {
        switch key {
        case "spc": "Space"
        case "ret": "Return"
        case "tab": "Tab"
        case "bspc": "Delete"
        case "esc": "Esc"
        case "caps": "Caps"
        case "lsft", "rsft": "Shift"
        case "lctl", "rctl": "Ctrl"
        case "lalt", "ralt": "Opt"
        case "lmet", "rmet": "Cmd"
        case "grv": "`"
        case "left": "←"
        case "rght": "→"
        case "up": "↑"
        case "down": "↓"
        default: key.uppercased()
        }
    }

    /// Convert a SwiftUI KeyPress character to a PhysicalKey for adding to queue
    nonisolated static func physicalKeyFromCharacter(_ character: Character) -> PhysicalKey? {
        let char = character.lowercased()

        // Character to key code mapping
        let keyCodeMap: [String: UInt16] = [
            // Letters
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
            "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
            "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "o": 31, "u": 32, "i": 34, "p": 35,
            "l": 37, "j": 38, "k": 40,
            "n": 45, "m": 46,

            // Numbers
            "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22,
            "7": 26, "8": 28, "9": 25, "0": 29,

            // Punctuation
            "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42,
            ";": 41, "'": 39, "`": 50, ",": 43, ".": 47, "/": 44,

            // Space
            " ": 49
        ]

        guard let keyCode = keyCodeMap[char] else { return nil }

        return PhysicalKey(
            keyCode: keyCode,
            label: char.uppercased(),
            x: 0,
            y: 0
        )
    }
}

// MARK: - Testing Support

extension SimulatorViewModel {
    /// Create a ViewModel with a custom service (for testing)
    static func forTesting(service: SimulatorService) -> SimulatorViewModel {
        SimulatorViewModel(service: service)
    }
}
