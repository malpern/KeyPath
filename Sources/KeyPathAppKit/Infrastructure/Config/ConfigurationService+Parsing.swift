import Foundation
import KeyPathCore

extension ConfigurationService {
    /// Parse configuration from string content
    public func parseConfigurationFromString(_ content: String) throws -> KanataConfiguration {
        // Use the existing validate method which handles parsing
        try validate(content: content)
    }

    /// Extract key mappings from Kanata configuration content
    func extractKeyMappingsFromContent(_ configContent: String) -> [KeyMapping] {
        var mappings: [KeyMapping] = []
        let lines = configContent.components(separatedBy: .newlines)

        var inDefsrc = false
        var inDeflayer = false
        var srcKeys: [String] = []
        var layerKeys: [String] = []

        for line in lines {
            let trimmed = KanataConfigTokenizer.stripInlineComment(line)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("(defsrc") {
                inDefsrc = true
                inDeflayer = false
                continue
            } else if trimmed.hasPrefix("(deflayer") {
                inDefsrc = false
                inDeflayer = true
                continue
            } else if trimmed == ")" {
                inDefsrc = false
                inDeflayer = false
                continue
            }

            if inDefsrc, !trimmed.isEmpty, !trimmed.hasPrefix(";") {
                srcKeys.append(contentsOf: KanataConfigTokenizer.tokenize(trimmed))
            } else if inDeflayer, !trimmed.isEmpty, !trimmed.hasPrefix(";") {
                layerKeys.append(contentsOf: KanataConfigTokenizer.tokenize(trimmed))
            }
        }

        // Match up src and layer keys, filtering out invalid keys
        var tempMappings: [KeyMapping] = []
        for (index, srcKey) in srcKeys.enumerated() where index < layerKeys.count {
            // Skip obviously invalid keys
            if srcKey != "invalid", !srcKey.isEmpty {
                tempMappings.append(KeyMapping(input: srcKey, output: layerKeys[index]))
            }
        }

        // Deduplicate mappings - keep only the last mapping for each input key
        var seenInputs: Set<String> = []
        for mapping in tempMappings.reversed() where !seenInputs.contains(mapping.input) {
            mappings.insert(mapping, at: 0)
            seenInputs.insert(mapping.input)
        }

        AppLogger.shared.log(
            "🔍 [Parse] Found \(srcKeys.count) src keys, \(layerKeys.count) layer keys, deduplicated to \(mappings.count) unique mappings"
        )
        return mappings
    }
}
