import Foundation

class KanataKeyValidator {
    
    func suggestKeyCorrection(_ keyName: String) -> String {
        let lower = keyName.lowercased()

        // Common corrections
        let corrections: [String: String] = [
            "capslock": "caps",
            "cap": "caps",
            "escape": "esc",
            "control": "lctl",
            "ctrl": "lctl",
            "shift": "lsft",
            "command": "lmet",
            "cmd": "lmet",
            "option": "lalt",
            "alt": "lalt",
            "space": "spc",
            "spacebar": "spc",
            "enter": "ret",
            "return": "ret",
            "backspace": "bspc",
            "delete": "del",
            "tab": "tab"
        ]

        if let correction = corrections[lower] {
            return correction
        }

        // Fuzzy matching for single character typos
        let validKeys = ["caps", "esc", "lctl", "rctl", "lsft", "rsft", "lalt", "ralt", "spc", "ret", "tab", "bspc", "del"]

        for validKey in validKeys {
            if levenshteinDistance(lower, validKey) <= 2 {
                return validKey
            }
        }

        return ""
    }
    
    func isValidKeyName(_ keyName: String) -> Bool {
        let validKeys = [
            // Letters
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
            "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
            // Numbers
            "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
            // Special keys
            "caps", "esc", "ret", "spc", "tab", "bspc", "del",
            "lsft", "rsft", "lctl", "rctl", "lalt", "ralt", "lmet", "rmet",
            "home", "end", "pgup", "pgdn", "up", "down", "left", "right",
            "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
            // Symbols
            "minus", "equal", "lbkt", "rbkt", "bslh", "scln", "quot", "grv",
            "comm", "dot", "slsh"
        ]

        return validKeys.contains(keyName.lowercased()) || keyName.count == 1
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Length = s1Array.count
        let s2Length = s2Array.count

        var matrix = Array(repeating: Array(repeating: 0, count: s2Length + 1), count: s1Length + 1)

        for i in 0...s1Length { matrix[i][0] = i }
        for j in 0...s2Length { matrix[0][j] = j }

        for i in 1...s1Length {
            for j in 1...s2Length {
                if s1Array[i-1] == s2Array[j-1] {
                    matrix[i][j] = matrix[i-1][j-1]
                } else {
                    matrix[i][j] = min(matrix[i-1][j], matrix[i][j-1], matrix[i-1][j-1]) + 1
                }
            }
        }

        return matrix[s1Length][s2Length]
    }
}