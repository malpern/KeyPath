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
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"

        // Row 4: Bottom row (ZXCV...)
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"

        // Row 2: Top row (QWERTY...)
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"

        // Row 1: Number row
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"

        // More top row keys
        case 30: return "]"
        case 31: return "o"
        case 32: return "u"
        case 33: return "["
        case 34: return "i"
        case 35: return "p"

        // Home row continued
        case 36: return "ret"
        case 37: return "l"
        case 38: return "j"
        case 39: return "'"
        case 40: return "k"
        case 41: return ";"
        case 42: return "\\"

        // Bottom row continued
        case 43: return ","
        case 44: return "/"
        case 45: return "n"
        case 46: return "m"
        case 47: return "."

        // Special keys
        case 48: return "tab"
        case 49: return "spc"
        case 50: return "grv"  // Backtick/grave
        case 51: return "bspc" // Backspace/Delete
        case 53: return "esc"

        // Modifiers
        case 54: return "rmet" // Right Command
        case 55: return "lmet" // Left Command
        case 56: return "lsft" // Left Shift
        case 57: return "caps"
        case 58: return "lalt" // Left Option
        case 59: return "lctl" // Left Control
        case 60: return "rsft" // Right Shift
        case 61: return "ralt" // Right Option
        case 63: return "fn"

        // Function keys
        case 96: return "f5"
        case 97: return "f6"
        case 98: return "f7"
        case 99: return "f3"
        case 100: return "f8"
        case 101: return "f9"
        case 103: return "f11"
        case 109: return "f10"
        case 111: return "f12"
        case 118: return "f4"
        case 120: return "f2"
        case 122: return "f1"

        // Arrow keys
        case 123: return "left"
        case 124: return "rght"
        case 125: return "down"
        case 126: return "up"

        default:
            return "unknown-\(keyCode)"
        }
    }

    /// Get a display label for a Kanata key name
    nonisolated static func displayLabelForKanataKey(_ key: String) -> String {
        switch key {
        case "spc": return "Space"
        case "ret": return "Return"
        case "tab": return "Tab"
        case "bspc": return "Delete"
        case "esc": return "Esc"
        case "caps": return "Caps"
        case "lsft", "rsft": return "Shift"
        case "lctl", "rctl": return "Ctrl"
        case "lalt", "ralt": return "Opt"
        case "lmet", "rmet": return "Cmd"
        case "grv": return "`"
        case "left": return "←"
        case "rght": return "→"
        case "up": return "↑"
        case "down": return "↓"
        default: return key.uppercased()
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
