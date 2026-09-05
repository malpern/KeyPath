import Foundation
import KeyPathCore

/// Renders simple modifications sentinel blocks without writing files.
public final class SimpleModsWriter: Sendable {
    private let configPath: String

    public init(configPath: String) {
        self.configPath = configPath
    }

    /// Render a proposed revision. Persistence belongs to SaveCoordinator.
    public func renderBlock(mappings: [SimpleMapping], in content: String) throws -> String {
        let lines = content.components(separatedBy: .newlines)

        // Find existing block
        let parser = SimpleModsParser(configPath: configPath)
        let (existingBlock, _, _) = try parser.parse(content: content)

        let blockId = existingBlock?.id ?? UUID().uuidString
        let blockVersion = existingBlock?.version ?? 1

        // Generate mapping lines
        var mappingLines: [String] = []
        mappingLines.append("  ;; Simple Modifications (managed by KeyPath)")

        // Deduplicate: keep only last mapping per fromKey
        var seenFromKeys: Set<String> = []
        var uniqueMappings: [SimpleMapping] = []
        for mapping in mappings.reversed() where !seenFromKeys.contains(mapping.fromKey) {
            uniqueMappings.insert(mapping, at: 0)
            seenFromKeys.insert(mapping.fromKey)
        }

        for mapping in uniqueMappings {
            if mapping.enabled {
                mappingLines.append("  \(mapping.fromKey) \(mapping.toKey)")
            } else {
                // Commented-out disabled line; still tracked by our parser
                mappingLines.append("  ;; \(mapping.fromKey) \(mapping.toKey)  ;; KP:DISABLED")
            }
        }

        // If no mappings remain, remove the entire sentinel block if it exists
        if uniqueMappings.isEmpty {
            var newLines: [String] = []
            if let existing = existingBlock {
                for (index, line) in lines.enumerated() {
                    let lineNumber = index + 1
                    if lineNumber < existing.startLine || lineNumber > existing.endLine {
                        newLines.append(line)
                    }
                }
                // Trim trailing empties
                while let last = newLines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    newLines.removeLast()
                }
                let newContent = newLines.joined(separator: "\n") + "\n"

                // SAFETY: Never write empty config - this would break kanata
                let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.contains("defsrc") || trimmed.contains("deflayer") else {
                    AppLogger.shared.errorUnlessQuietTest("🛑 [SimpleModsWriter] BLOCKED: Would have written invalid config")
                    throw KeyPathError.configuration(.invalidFormat(reason: "Cannot write empty or invalid configuration"))
                }

                // A config still needs a layer when its final mapping is removed.
                // Keep an empty managed base layer unless another layer survives.
                if newContent.range(of: #"(?m)^\s*\(deflayer(?:map)?\s"#, options: .regularExpression) != nil {
                    return newContent
                }
            } else {
                // Nothing to do if there is no block
                return content
            }
        }

        // Generate block content
        let blockContent = """
        ;; KP:BEGIN simple_mods id=\(blockId) version=\(blockVersion)
        (deflayermap (base)
        \(mappingLines.joined(separator: "\n"))
        )
        ;; KP:END id=\(blockId)
        """

        // Insert or replace block
        var newLines: [String] = []

        if let existing = existingBlock {
            // Replace existing block
            for (index, line) in lines.enumerated() {
                let lineNumber = index + 1
                if lineNumber < existing.startLine || lineNumber > existing.endLine {
                    newLines.append(line)
                } else if lineNumber == existing.startLine {
                    // Insert new block at start position
                    newLines.append(contentsOf: blockContent.components(separatedBy: .newlines))
                }
            }
        } else {
            // Append new block
            newLines = lines
            if !newLines.isEmpty, let lastLine = newLines.last, !lastLine.isEmpty {
                newLines.append("")
            }
            newLines.append("")
            newLines.append(contentsOf: blockContent.components(separatedBy: .newlines))
        }

        return newLines.joined(separator: "\n")
    }

    /// Generate effective config content (source config with disabled lines filtered out)
    public func generateEffectiveConfig() throws -> String {
        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        let parser = SimpleModsParser(configPath: configPath)
        let (block, _, _) = try parser.parse()

        guard let block else {
            // No block means no filtering needed
            return content
        }

        // Filter out disabled lines within the block
        var effectiveLines: [String] = []
        var inBlock = false

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1

            // Check if entering block
            if lineNumber == block.startLine {
                // Do NOT include sentinel begin line in effective config
                inBlock = true
                continue
            }

            // Check if exiting block
            if lineNumber == block.endLine {
                // Do NOT include sentinel end line in effective config
                inBlock = false
                continue
            }

            // Inside block - filter disabled lines (commented with ';' and/or carrying KP:DISABLED marker)
            if inBlock {
                if line.contains("KP:DISABLED") || line.trimmingCharacters(in: .whitespaces).hasPrefix(";") {
                    // Skip this line entirely
                    continue
                }
            }

            effectiveLines.append(line)
        }

        return effectiveLines.joined(separator: "\n")
    }
}
