import Foundation

class KanataKeyValidator {
    private let llmProvider: AnthropicModelProvider?
    
    // Cache for validated keys to reduce API calls
    private var validationCache: [String: Bool] = [:]
    private var correctionCache: [String: String] = [:]
    
    init(llmProvider: AnthropicModelProvider? = nil) {
        self.llmProvider = llmProvider
        setupKnownKeyCache()
    }

    func suggestKeyCorrection(_ keyName: String) -> String {
        let lower = keyName.lowercased()
        
        // Check cache first
        if let cachedCorrection = correctionCache[lower] {
            return cachedCorrection
        }
        
        // Try comprehensive hardcoded corrections first (fast path)
        let correction = getHardcodedCorrection(lower)
        if !correction.isEmpty {
            correctionCache[lower] = correction
            return correction
        }
        
        // Fall back to LLM for complex cases
        if let llmProvider = llmProvider {
            let llmCorrection = getLLMKeyCorrection(keyName, provider: llmProvider)
            correctionCache[lower] = llmCorrection
            return llmCorrection
        }
        
        // Final fallback: fuzzy matching
        let fuzzyCorrection = getFuzzyCorrection(lower)
        correctionCache[lower] = fuzzyCorrection
        return fuzzyCorrection
    }

    func isValidKeyName(_ keyName: String) -> Bool {
        let lower = keyName.lowercased()
        
        // Check cache first
        if let cachedResult = validationCache[lower] {
            return cachedResult
        }
        
        // Fast path: check comprehensive known keys
        let isKnownValid = isKnownValidKey(lower)
        if isKnownValid {
            validationCache[lower] = true
            return true
        }
        
        // LLM validation for unknown keys
        if let llmProvider = llmProvider {
            let isLLMValid = isLLMValidKey(keyName, provider: llmProvider)
            validationCache[lower] = isLLMValid
            return isLLMValid
        }
        
        // Fallback: basic validation
        let isBasicValid = isBasicValidKey(lower)
        validationCache[lower] = isBasicValid
        return isBasicValid
    }
    
    // MARK: - Private Methods
    
    private func setupKnownKeyCache() {
        // Pre-populate cache with definitely valid keys to avoid LLM calls
        let definitelyValid = [
            "caps", "esc", "ret", "spc", "tab", "bspc", "del",
            "lsft", "rsft", "lctl", "rctl", "lalt", "ralt", "lmet", "rmet",
            "home", "end", "pgup", "pgdn", "up", "down", "left", "right",
            "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
            "minus", "equal", "lbkt", "rbkt", "bslh", "scln", "quot", "grv",
            "comm", "dot", "slsh", "ins", "pause", "prnt", "slck", "menu"
        ]
        
        for key in definitelyValid {
            validationCache[key] = true
        }
        
        // Pre-populate alphabet and numbers
        for char in "abcdefghijklmnopqrstuvwxyz0123456789" {
            validationCache[String(char)] = true
        }
    }
    
    private func getHardcodedCorrection(_ keyName: String) -> String {
        // Comprehensive key mappings (extends existing + adds more)
        let corrections: [String: String] = [
            // Basic corrections
            "capslock": "caps", "cap": "caps", "caps lock": "caps",
            "escape": "esc", "esc key": "esc",
            "control": "lctl", "ctrl": "lctl", "left control": "lctl", "left ctrl": "lctl",
            "right control": "rctl", "right ctrl": "rctl",
            "shift": "lsft", "left shift": "lsft", "right shift": "rsft",
            "command": "lmet", "cmd": "lmet", "left command": "lmet", "left cmd": "lmet",
            "right command": "rmet", "right cmd": "rmet",
            "option": "lalt", "alt": "lalt", "left option": "lalt", "left alt": "lalt",
            "right option": "ralt", "right alt": "ralt",
            "space": "spc", "spacebar": "spc", "space bar": "spc",
            "return": "ret", "enter": "ret", "enter key": "ret",
            "backspace": "bspc", "back space": "bspc", "back": "bspc",
            "delete": "del", "del key": "del",
            
            // Arrow keys
            "up arrow": "up", "arrow up": "up", "↑": "up",
            "down arrow": "down", "arrow down": "down", "↓": "down", 
            "left arrow": "left", "arrow left": "left", "←": "left",
            "right arrow": "right", "arrow right": "right", "→": "right",
            
            // Navigation
            "page up": "pgup", "pageup": "pgup", "pg up": "pgup",
            "page down": "pgdn", "pagedown": "pgdn", "pg down": "pgdn", "pg dn": "pgdn",
            "home key": "home", "end key": "end",
            
            // Function keys
            "function 1": "f1", "function 2": "f2", "function 3": "f3", "function 4": "f4",
            "function 5": "f5", "function 6": "f6", "function 7": "f7", "function 8": "f8",
            "function 9": "f9", "function 10": "f10", "function 11": "f11", "function 12": "f12",
            
            // Symbols
            "dash": "minus", "hyphen": "minus", "-": "minus",
            "equals": "equal", "=": "equal",
            "left bracket": "lbkt", "[": "lbkt", "open bracket": "lbkt",
            "right bracket": "rbkt", "]": "rbkt", "close bracket": "rbkt",
            "backslash": "bslh", "\\": "bslh",
            "semicolon": "scln", ";": "scln",
            "quote": "quot", "'": "quot", "apostrophe": "quot",
            "backtick": "grv", "`": "grv", "grave": "grv",
            "comma": "comm", ",": "comm",
            "period": "dot", ".": "dot", "full stop": "dot",
            "slash": "slsh", "/": "slsh", "forward slash": "slsh"
        ]
        
        return corrections[keyName] ?? ""
    }
    
    private func isKnownValidKey(_ keyName: String) -> Bool {
        // Check if already in validation cache
        if let cachedResult = validationCache[keyName] {
            return cachedResult
        }
        
        // Single characters are generally valid
        if keyName.count == 1 {
            return true
        }
        
        // Function keys f1-f24
        if keyName.hasPrefix("f") && keyName.count <= 3 {
            if let number = Int(String(keyName.dropFirst())), number >= 1 && number <= 24 {
                return true
            }
        }
        
        // Check if we can correct it (if correctable, it means we understand it)
        return !getHardcodedCorrection(keyName).isEmpty
    }
    
    private func isBasicValidKey(_ keyName: String) -> Bool {
        // Fallback validation - similar to original but more comprehensive
        let basicValidKeys = [
            "caps", "esc", "ret", "spc", "tab", "bspc", "del",
            "lsft", "rsft", "lctl", "rctl", "lalt", "ralt", "lmet", "rmet",
            "home", "end", "pgup", "pgdn", "up", "down", "left", "right",
            "minus", "equal", "lbkt", "rbkt", "bslh", "scln", "quot", "grv",
            "comm", "dot", "slsh", "ins", "pause", "prnt", "slck", "menu"
        ]
        
        return basicValidKeys.contains(keyName) || keyName.count == 1
    }
    
    private func getLLMKeyCorrection(_ keyName: String, provider: AnthropicModelProvider) -> String {
        // Use LLM to intelligently correct key names
        let prompt = """
        You are a Kanata keyboard configuration expert. The user typed a key name that needs to be converted to valid Kanata syntax.
        
        User input: "\(keyName)"
        
        Convert this to the correct Kanata key name. Respond with ONLY the correct key name, nothing else.
        
        Valid Kanata key examples:
        - caps (Caps Lock)
        - esc (Escape) 
        - lctl/rctl (Left/Right Control)
        - lsft/rsft (Left/Right Shift)
        - lalt/ralt (Left/Right Alt)
        - lmet/rmet (Left/Right Command)
        - spc (Space)
        - ret (Return/Enter)
        - bspc (Backspace)
        - del (Delete)
        - up/down/left/right (Arrow keys)
        - f1-f12 (Function keys)
        - a-z, 0-9 (Letters and numbers)
        - home, end, pgup, pgdn
        - tab, ins, pause, prnt, slck, menu
        
        If the input is not a valid key name or you're unsure, respond with an empty string.
        """
        
        // Synchronous LLM call for this use case
        // Note: In production, this might want to be async, but the interface requires sync
        do {
            let semaphore = DispatchSemaphore(value: 0)
            var result = ""
            
            Task {
                do {
                    let response = try await provider.sendMessage(prompt)
                    result = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    semaphore.signal()
                } catch {
                    semaphore.signal()
                }
            }
            
            semaphore.wait()
            return result
        }
    }
    
    private func isLLMValidKey(_ keyName: String, provider: AnthropicModelProvider) -> Bool {
        let correction = getLLMKeyCorrection(keyName, provider: provider)
        return !correction.isEmpty
    }
    
    private func getFuzzyCorrection(_ keyName: String) -> String {
        // Fallback fuzzy matching (original logic)
        let validKeys = ["caps", "esc", "lctl", "rctl", "lsft", "rsft", "lalt", "ralt", "spc", "ret", "tab", "bspc", "del"]
        
        for validKey in validKeys where levenshteinDistance(keyName, validKey) <= 2 {
            return validKey
        }
        
        return ""
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Length = s1Array.count
        let s2Length = s2Array.count

        var matrix = Array(repeating: Array(repeating: 0, count: s2Length + 1), count: s1Length + 1)

        for index in 0...s1Length { matrix[index][0] = index }
        for index in 0...s2Length { matrix[0][index] = index }

        for firstIndex in 1...s1Length {
            for secondIndex in 1...s2Length {
                if s1Array[firstIndex-1] == s2Array[secondIndex-1] {
                    matrix[firstIndex][secondIndex] = matrix[firstIndex-1][secondIndex-1]
                } else {
                    matrix[firstIndex][secondIndex] = min(
                        matrix[firstIndex-1][secondIndex], 
                        matrix[firstIndex][secondIndex-1], 
                        matrix[firstIndex-1][secondIndex-1]
                    ) + 1
                }
            }
        }

        return matrix[s1Length][s2Length]
    }
}
