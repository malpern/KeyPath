import Foundation

/// Parser for reading and indexing simple modifications sentinel blocks
@MainActor
public final class SimpleModsParser {
    private let configPath: String

    public init(configPath: String) {
        self.configPath = configPath
    }

    /// Parse the config file and find all simple mods sentinel blocks
    public func parse() throws -> (
        block: SentinelBlock?, allMappings: [SimpleMapping], conflicts: [MappingConflict]
    ) {
        guard FileManager.default.fileExists(atPath: configPath) else {
            // No config file means no block
            return (nil, [], [])
        }

        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        // Find sentinel block
        var sentinelBlock: SentinelBlock?
        var conflicts: [MappingConflict] = []

        // Track all mappings in the file (for conflict detection)
        var allMappings: [SimpleMapping] = []

        // Find KP:BEGIN sentinel
        var inBlock = false
        var blockStartLine: Int?
        var blockId: String?
        var blockVersion = 1
        var blockMappings: [SimpleMapping] = []
        var currentMappingLine: Int?
        var currentFromKey: String?

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for KP:BEGIN (accept both '#' and ';' comment styles)
            if trimmed.hasPrefix("# KP:BEGIN") || trimmed.hasPrefix("; KP:BEGIN")
                || trimmed.hasPrefix(";; KP:BEGIN")
            {
                if inBlock {
                    // Nested block - not expected but handle gracefully
                    continue
                }

                // Parse attributes
                let attributes = parseAttributes(from: trimmed)
                if attributes["simple_mods"] != nil || attributes["simple_mod"] != nil {
                    inBlock = true
                    blockStartLine = lineNumber
                    blockId = attributes["id"] ?? UUID().uuidString
                    blockVersion = Int(attributes["version"] ?? "1") ?? 1
                }
                continue
            }

            // Check for KP:END (accept both '#' and ';' comment styles)
            if trimmed.hasPrefix("# KP:END") || trimmed.hasPrefix("; KP:END")
                || trimmed.hasPrefix(";; KP:END")
            {
                if inBlock {
                    let endId = parseAttributes(from: trimmed)["id"]
                    if endId == blockId {
                        // Complete block found
                        sentinelBlock = SentinelBlock(
                            id: blockId ?? UUID().uuidString,
                            version: blockVersion,
                            startLine: blockStartLine ?? lineNumber,
                            endLine: lineNumber,
                            mappings: blockMappings
                        )
                        inBlock = false
                        blockStartLine = nil
                        blockId = nil
                        blockMappings = []
                    }
                }
                continue
            }

            // If we're in the block, look for deflayermap content
            if inBlock {
                // Look for deflayermap (base) start
                if trimmed.contains("(deflayermap"), trimmed.contains("(base)") {
                    currentMappingLine = lineNumber
                    continue
                }

                // Look for mapping lines: "from to" or "from to # KP:DISABLED"
                if let mapping = parseMappingLine(line, at: lineNumber) {
                    if mapping.fromKey == currentFromKey {
                        // Duplicate within block - conflict
                        conflicts.append(
                            MappingConflict(
                                fromKey: mapping.fromKey,
                                conflictingLine: lineNumber,
                                conflictingFile: configPath,
                                reason: "Duplicate mapping in same block"
                            ))
                    } else {
                        blockMappings.append(mapping)
                        allMappings.append(mapping)
                        currentFromKey = mapping.fromKey
                    }
                    currentMappingLine = lineNumber
                }

                // Check for closing paren of deflayermap
                if trimmed == ")", currentMappingLine != nil {
                    currentMappingLine = nil
                    currentFromKey = nil
                }
            } else {
                // Outside block - check for conflicts (other deflayermap mappings)
                if let mapping = parseMappingLine(line, at: lineNumber) {
                    // Check if this conflicts with any in our block
                    if blockMappings.contains(where: { $0.fromKey == mapping.fromKey }) {
                        conflicts.append(
                            MappingConflict(
                                fromKey: mapping.fromKey,
                                conflictingLine: lineNumber,
                                conflictingFile: configPath,
                                reason: "Mapping exists outside managed block"
                            ))
                    }
                    allMappings.append(mapping)
                }
            }
        }

        return (sentinelBlock, allMappings, conflicts)
    }

    /// Parse a mapping line like "caps esc" or "caps esc # KP:DISABLED"
    private func parseMappingLine(_ line: String, at lineNumber: Int) -> SimpleMapping? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Handle disabled/commented mapping lines beginning with ';'
        var disabled = false
        var content = trimmed
        if trimmed.hasPrefix(";") {
            // Strip leading ';' and any following spaces to parse mapping tokens
            disabled = true
            content = String(trimmed.drop(while: { $0 == ";" || $0 == " " }))
        }

        if content.isEmpty || content.hasPrefix("#") {
            return nil
        }

        // Skip deflayermap declaration line
        if content.contains("(deflayermap") || content == ")" {
            return nil
        }

        // Parse key pair
        let parts = content.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 2 else {
            return nil
        }

        let fromKey = parts[0]
        let toKey = parts[1]

        // Check if disabled marker present anywhere
        let isDisabled = disabled || trimmed.contains("KP:DISABLED")

        // Validate keys (basic check)
        if !isValidKanataKey(fromKey) || !isValidKanataKey(toKey) {
            return nil
        }

        return SimpleMapping(
            fromKey: fromKey,
            toKey: toKey,
            enabled: !isDisabled,
            filePath: configPath,
            lineRange: lineNumber ... lineNumber
        )
    }

    /// Parse attributes from a sentinel line like "# KP:BEGIN simple_mods id=abc version=1"
    private func parseAttributes(from line: String) -> [String: String] {
        var attributes: [String: String] = [:]

        // Extract type (simple_mods or simple_mod)
        if line.contains("simple_mods") {
            attributes["simple_mods"] = "true"
        } else if line.contains("simple_mod") {
            attributes["simple_mod"] = "true"
        }

        // Parse key=value pairs
        let parts = line.components(separatedBy: .whitespaces)
        for part in parts where part.contains("=") {
            let keyValue = part.components(separatedBy: "=")
            if keyValue.count == 2 {
                let key = keyValue[0].trimmingCharacters(in: .whitespaces)
                let value = keyValue[1].trimmingCharacters(in: .whitespaces)
                attributes[key] = value
            }
        }

        return attributes
    }

    /// Validate if a string is a valid Kanata key name
    private func isValidKanataKey(_ key: String) -> Bool {
        // Basic validation - non-empty, no spaces, no special chars that break syntax
        if key.isEmpty || key.contains(" ") || key.contains("(") || key.contains(")") {
            return false
        }

        // Known valid keys (non-exhaustive but covers common cases)
        let validKeys: Set<String> = [
            "caps", "esc", "lctl", "rctl", "lsft", "rsft",
            "lalt", "ralt", "lmet", "rmet", "spc", "ret",
            "tab", "bspc", "del", "f1", "f2", "f3", "f4",
            "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
            "f13", "f14", "f15", "playpause", "volup", "voldown",
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
            "k", "l", "m", "n", "o", "p", "q", "r", "s", "t",
            "u", "v", "w", "x", "y", "z"
        ]

        return validKeys.contains(key.lowercased())
    }
}
