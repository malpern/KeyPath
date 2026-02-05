import AppKit
import Carbon
import Combine
import Foundation
import KeyPathCore
import SwiftUI

extension KeyboardVisualizationViewModel {
    // MARK: - Test hooks (DEBUG only)

    /// Simulate a HoldActivated TCP event (used by unit tests).
    func simulateHoldActivated(key: String, action: String) {
        handleHoldActivated(key: key, action: action)
    }

    /// Simulate a TapActivated TCP event (used by unit tests).
    func simulateTapActivated(key: String, action: String) {
        handleTapActivated(key: key, action: action)
    }

    /// Simulate a TCP KeyInput event (used by unit tests).
    func simulateTcpKeyInput(key: String, action: String) {
        handleTcpKeyInput(key: key, action: action)
    }

    /// Maps Kanata key names (e.g., "h", "j", "space") to macOS key codes
    /// This is the inverse of OverlayKeyboardView.keyCodeToKanataName()
    nonisolated static func kanataNameToKeyCode(_ name: String) -> UInt16? {
        // Map from lowercase Kanata key names to macOS virtual key codes
        let mapping: [String: UInt16] = [
            // Row 3: Home row (ASDF...)
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
            // Row 4: Bottom row (ZXCV...)
            "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
            // Row 2: Top row (QWERTY...)
            "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            // Row 1: Number row
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
            "equal": 24, "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29,
            // More top row keys
            "rightbrace": 30, "o": 31, "u": 32, "leftbrace": 33, "i": 34, "p": 35,
            // Home row continued
            "enter": 36, "ret": 36, "return": 36,
            "l": 37, "j": 38, "apostrophe": 39, "k": 40, "semicolon": 41, "backslash": 42,
            // Bottom row continued
            "comma": 43, "slash": 44, "n": 45, "m": 46, "dot": 47,
            // Special keys
            "tab": 48, "space": 49, "spc": 49, "grave": 50, "grv": 50,
            "backspace": 51, "bspc": 51, "esc": 53, "escape": 53,
            // Modifiers
            "rightmeta": 54, "rmet": 54, "leftmeta": 55, "lmet": 55,
            "leftshift": 56, "lsft": 56, "capslock": 57, "caps": 57,
            "leftalt": 58, "lalt": 58, "leftctrl": 59, "lctl": 59,
            "rightshift": 60, "rsft": 60, "rightalt": 61, "ralt": 61,
            "fn": 63,
            // Function keys
            "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101,
            "f11": 103, "f10": 109, "f12": 111, "f4": 118, "f2": 120, "f1": 122,
            // Arrow keys
            "left": 123, "right": 124, "down": 125, "up": 126,
            // Navigation keys
            "home": 115,
            "pageup": 116, "pgup": 116,
            "del": 117, "delete": 117,
            "end": 119,
            "pagedown": 121, "pgdn": 121,
            "help": 114, "insert": 114,
            // Extended function keys
            "f13": 105,
            "f14": 107,
            "f15": 113,
            "f16": 106,
            "f17": 64,
            "f18": 79,
            "f19": 80,
            // Right Control
            "rightctrl": 102, "rctl": 102,
            // ISO key (between Left Shift and Z on ISO keyboards)
            "intlbackslash": 10,
            // ABNT2 key (between slash and right shift on Brazilian keyboards)
            "intlro": 94,
            // Korean language keys
            "hangeul": 104, "hanja": 104
        ]
        return mapping[name.lowercased()]
    }
}
