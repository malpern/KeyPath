import Foundation

extension KanataRule {
    static func parseEnhanced(from text: String) -> KanataRule? {
        // Extract JSON from markdown code block
        let pattern = "```json\\s*([\\s\\S]*?)\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            // Fallback to old format
            return parseOldFormat(from: text)
        }
        
        let jsonString = String(text[range])
        guard let jsonData = jsonString.data(using: .utf8) else {
            return parseOldFormat(from: text)
        }
        
        let decoder = JSONDecoder()
        
        // Try to decode the new enhanced format
        if let enhancedRule = try? decoder.decode(EnhancedKanataRule.self, from: jsonData) {
            return enhancedRule.toKanataRule()
        }
        
        // Fallback to old format
        return parseOldFormat(from: text)
    }
    
    private static func parseOldFormat(from text: String) -> KanataRule? {
        // Try to parse the old simple format
        let pattern = "```json\\s*([\\s\\S]*?)\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        
        let jsonString = String(text[range])
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let oldRule = try decoder.decode(OldKanataRule.self, from: jsonData)
            
            // Convert to new format
            let enhancedVisualization = EnhancedRemapVisualization(
                behavior: .simpleRemap(from: oldRule.visualization.from, toKey: oldRule.visualization.toKey),
                title: "Simple Remap",
                description: "Maps \(oldRule.visualization.from) to \(oldRule.visualization.toKey)"
            )
            
            return KanataRule(
                visualization: enhancedVisualization,
                kanataRule: oldRule.kanataRule,
                confidence: oldRule.confidence,
                explanation: oldRule.explanation
            )
        } catch {
            print("Failed to decode old KanataRule: \(error)")
            return nil
        }
    }
}

// Temporary struct for parsing enhanced format
private struct EnhancedKanataRule: Codable {
    let visualization: EnhancedVisualizationData
    let kanataRule: String
    let confidence: KanataRule.Confidence
    let explanation: String
    
    enum CodingKeys: String, CodingKey {
        case visualization
        case kanataRule = "kanata_rule"
        case confidence
        case explanation
    }
    
    func toKanataRule() -> KanataRule {
        return KanataRule(
            visualization: visualization.toEnhancedRemapVisualization(),
            kanataRule: kanataRule,
            confidence: confidence,
            explanation: explanation
        )
    }
}

private struct EnhancedVisualizationData: Codable {
    let behavior: BehaviorData
    let title: String
    let description: String
    
    func toEnhancedRemapVisualization() -> EnhancedRemapVisualization {
        return EnhancedRemapVisualization(
            behavior: behavior.toKanataBehavior(),
            title: title,
            description: description
        )
    }
}

private struct BehaviorData: Codable {
    let type: String
    let data: [String: AnyCodable]
    
    func toKanataBehavior() -> KanataBehavior {
        print("DEBUG: Parsing behavior type: '\(type)', data: \(data)")
        switch type {
        case "simpleRemap":
            let from = data["from"]?.stringValue ?? ""
            let toKey = data["toKey"]?.stringValue ?? data["to"]?.stringValue ?? ""
            return .simpleRemap(from: from, toKey: toKey)
            
        case "tapHold":
            let key = data["key"]?.stringValue ?? ""
            let tap = data["tap"]?.stringValue ?? data["tapAction"]?.stringValue ?? ""
            let hold = data["hold"]?.stringValue ?? data["holdAction"]?.stringValue ?? ""
            print("DEBUG: tapHold - key: '\(key)', tap: '\(tap)', hold: '\(hold)'")
            return .tapHold(key: key, tap: tap, hold: hold)
            
        case "tapDance":
            let key = data["key"]?.stringValue ?? ""
            let actionsData = data["actions"]?.arrayValue ?? []
            let actions = actionsData.compactMap { actionData -> TapDanceAction? in
                let dict = actionData.dictionaryValue
                guard let tapCount = dict["tapCount"]?.intValue,
                      let action = dict["action"]?.stringValue,
                      let description = dict["description"]?.stringValue else {
                    print("DEBUG: tapDance action parsing failed - tapCount: \(dict["tapCount"]?.intValue ?? -1), action: '\(dict["action"]?.stringValue ?? "nil")', description: '\(dict["description"]?.stringValue ?? "nil")')")
                    return nil
                }
                return TapDanceAction(tapCount: tapCount, action: action, description: description)
            }
            print("DEBUG: tapDance - key: '\(key)', actions count: \(actions.count)")
            for action in actions {
                print("DEBUG: tapDance action - tapCount: \(action.tapCount), action: '\(action.action)', description: '\(action.description)'")
            }
            return .tapDance(key: key, actions: actions)
            
        case "sequence":
            let trigger = data["trigger"]?.stringValue ?? ""
            let sequence = data["sequence"]?.arrayValue.compactMap { $0.stringValue } ?? []
            return .sequence(trigger: trigger, sequence: sequence)
            
        case "combo":
            let keys = data["keys"]?.arrayValue.compactMap { $0.stringValue } ?? []
            let result = data["result"]?.stringValue ?? ""
            return .combo(keys: keys, result: result)
            
        case "layer":
            let key = data["key"]?.stringValue ?? ""
            let layerName = data["layerName"]?.stringValue ?? ""
            let mappingsData = data["mappings"]?.dictionaryValue ?? [:]
            var mappings: [String: String] = [:]
            for (key, value) in mappingsData {
                if let stringValue = value.stringValue {
                    mappings[key] = stringValue
                }
            }
            return .layer(key: key, layerName: layerName, mappings: mappings)
            
        default:
            // Fallback to simple remap
            print("DEBUG: Unknown behavior type '\(type)' - falling back to Unknown/Unknown")
            return .simpleRemap(from: "Unknown", toKey: "Unknown")
        }
    }
}

// Old format for backward compatibility
private struct OldKanataRule: Codable {
    let visualization: RemapVisualization
    let kanataRule: String
    let confidence: KanataRule.Confidence
    let explanation: String
    
    enum CodingKeys: String, CodingKey {
        case visualization
        case kanataRule = "kanata_rule"
        case confidence
        case explanation
    }
}

// Helper for dynamic JSON parsing
private struct AnyCodable: Codable {
    let value: Any
    
    var stringValue: String? {
        return value as? String
    }
    
    var intValue: Int? {
        return value as? Int
    }
    
    var arrayValue: [AnyCodable] {
        return (value as? [Any])?.map { AnyCodable(value: $0) } ?? []
    }
    
    var dictionaryValue: [String: AnyCodable] {
        return (value as? [String: Any])?.mapValues { AnyCodable(value: $0) } ?? [:]
    }
    
    init(value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
