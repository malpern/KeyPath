import Foundation

class KanataRuleSuggestionProvider {

    func suggestRuleFormat(_ input: String) -> String {
        let lower = input.lowercased()

        if lower.contains("caps") && lower.contains("esc") {
            return "Try: 'caps -> esc'"
        } else if lower.contains("space") && lower.contains("shift") {
            return "Try: 'spc -> lsft' for space to shift"
        } else if input.count == 1 {
            return "Try: '\(input) -> [target_key]' format"
        } else if lower.contains("to") {
            // Try to parse "x to y" format
            let parts = lower.components(separatedBy: " to ")
            if parts.count == 2 {
                let from = parts[0].trimmingCharacters(in: .whitespaces)
                let to = parts[1].trimmingCharacters(in: .whitespaces)
                return "Try: '\(from) -> \(to)'"
            }
        }

        return "Use format like 'caps -> esc' or 'a -> b'"
    }
}
