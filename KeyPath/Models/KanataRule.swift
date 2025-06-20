import Foundation

struct KanataRule: Codable {
    let visualization: EnhancedRemapVisualization
    let kanataRule: String
    let confidence: Confidence
    let explanation: String

    enum Confidence: String, Codable {
        case high
        case medium
        case low
    }

    enum CodingKeys: String, CodingKey {
        case visualization
        case kanataRule = "kanata_rule"
        case confidence
        case explanation
    }
}

// Keep the old struct for backward compatibility
struct RemapVisualization: Codable {
    let from: String
    let toKey: String

    // Convert to enhanced visualization
    var enhanced: EnhancedRemapVisualization {
        return EnhancedRemapVisualization(
            behavior: .simpleRemap(from: from, toKey: toKey),
            title: "Simple Remap",
            description: "Maps \(from) to \(toKey)"
        )
    }
}

extension KanataRule {
    static func parse(from text: String) -> KanataRule? {
        return parseEnhanced(from: text)
    }
    
    /// Returns the complete Kanata configuration for this rule
    var completeKanataConfig: String {
        // If the rule already contains complete config (defsrc/deflayer), return as-is
        if kanataRule.contains("(defsrc") && kanataRule.contains("(deflayer") {
            return kanataRule
        }
        
        // Otherwise, generate complete configuration from the behavior
        return KanataRuleGenerator.generateCompleteRule(from: visualization.behavior)
    }
    
    /// Returns a simplified display version of the rule (for UI display)
    var displayRule: String {
        // If it's a simple "a -> b" format, return as-is
        if kanataRule.contains(" -> ") {
            return kanataRule
        }
        
        // If it's a complete config, try to extract just the core rule
        if kanataRule.contains("(defalias") {
            // Extract just the defalias line
            if let defaliasRange = kanataRule.range(of: #"\(defalias[^\)]+\)"#, options: .regularExpression) {
                return String(kanataRule[defaliasRange])
            }
        }
        
        // Otherwise return the raw rule
        return kanataRule
    }
}
