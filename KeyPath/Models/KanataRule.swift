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
}
