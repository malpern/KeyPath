import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import Network

extension KanataConfiguration {
    // MARK: - Rendering helpers

    /// Render defvar block with timing variables for reuse across the config.
    /// These variables allow users to globally adjust timing values.
    static func renderDefvarBlock() -> String {
        """
        #|
        ================================================================================
        TIMING VARIABLES
        ================================================================================
        |#

        (defvar
          tap-timeout   200
          hold-timeout  200
          chord-timeout  50
        )

        """
    }

    static func renderAliasBlock(_ aliases: [AliasDefinition]) -> String {
        guard !aliases.isEmpty else { return "" }
        var lines = [
            "#|",
            "================================================================================",
            "ALIAS DEFINITIONS (defalias)",
            "================================================================================",
            "|#",
            "",
            "(defalias"
        ]
        let definitions = aliases.map { alias in
            // Format multi-line actions with proper indentation
            let formattedDef = formatMultiLineAction(alias.definition)
            return "  \(alias.aliasName) \(formattedDef)"
        }
        lines.append(contentsOf: definitions)
        lines.append(")")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Format complex actions across multiple lines for better readability.
    /// Handles common patterns like multi actions and long tap-hold chains.
    static func formatMultiLineAction(_ action: String) -> String {
        // If action already contains newlines (from our formatting), return as-is
        if action.contains("\n") {
            return action
        }

        // Only format if action is long enough to benefit from multi-line
        guard action.count > 80 else {
            return action
        }

        // Format multi actions with multiple components
        if action.hasPrefix("(multi "), action.count > 100 {
            return formatMultiAction(action)
        }

        // Format long tap-hold actions that contain multi
        if action.contains("(tap-hold") || action.contains("(tap-hold-press") || action.contains("(tap-hold-release"), action.contains("(multi ") {
            return formatTapHoldWithMulti(action)
        }

        // Otherwise, return as-is to avoid breaking valid syntax
        return action
    }

    /// Format a multi action across multiple lines.
    /// Only handles simple cases to avoid breaking valid syntax.
    static func formatMultiAction(_ action: String) -> String {
        // Extract components from (multi comp1 comp2 comp3)
        guard action.hasPrefix("(multi "), action.hasSuffix(")") else {
            return action
        }

        let inner = String(action.dropFirst(7).dropLast(1)) // Remove "(multi " and ")"

        // Count top-level components (separated by spaces at depth 0)
        var parenDepth = 0
        var componentCount = 0
        var lastWasSpace = false

        for char in inner {
            if char == "(" {
                parenDepth += 1
                lastWasSpace = false
            } else if char == ")" {
                parenDepth -= 1
                lastWasSpace = false
            } else if char == " ", parenDepth == 0 {
                if !lastWasSpace {
                    componentCount += 1
                }
                lastWasSpace = true
            } else {
                lastWasSpace = false
            }
        }

        // Only format if we have 3+ components (multi with 2+ items)
        guard componentCount >= 2 else {
            return action
        }

        // Simple formatting: split on spaces at depth 0
        var result = "(multi\n"
        var currentComponent = ""
        parenDepth = 0

        for char in inner {
            if char == "(" {
                currentComponent.append(char)
                parenDepth += 1
            } else if char == ")" {
                currentComponent.append(char)
                parenDepth -= 1
            } else if char == " ", parenDepth == 0 {
                // Space at top level - start new component
                let trimmed = currentComponent.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    result += "    \(trimmed)\n"
                }
                currentComponent = ""
            } else {
                currentComponent.append(char)
            }
        }

        // Add final component
        let trimmed = currentComponent.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result += "    \(trimmed)\n"
        }

        result += "  )"
        return result
    }

    /// Format tap-hold actions that contain multi sub-actions.
    static func formatTapHoldWithMulti(_ action: String) -> String {
        // Pattern: (tap-hold timeout timeout key (multi ...))
        // We want: (tap-hold timeout timeout key\n  (multi\n    ...))

        // Find the (multi part
        guard let multiStart = action.range(of: "(multi ") else {
            return action
        }

        let beforeMulti = String(action[..<multiStart.lowerBound]).trimmingCharacters(in: .whitespaces)
        let remaining = action[multiStart.lowerBound...]

        // Capture a balanced (multi ...) block and keep any trailing tokens (e.g., closing paren for tap-hold)
        var depth = 0
        var endIndex: String.Index?
        var index = remaining.startIndex
        while index < remaining.endIndex {
            let char = remaining[index]
            if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 {
                    endIndex = index
                    break
                }
            }
            index = remaining.index(after: index)
        }

        guard let endIndex else {
            return action
        }

        let multiPart = String(remaining[...endIndex])
        let trailing = String(remaining[remaining.index(after: endIndex)...])

        // Format the multi part
        let formattedMulti = formatMultiAction(multiPart)

        // Combine with proper indentation
        if formattedMulti.contains("\n") {
            let indentedMulti = formattedMulti.replacingOccurrences(of: "\n", with: "\n  ")
            let trimmedTrailing = trailing.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(beforeMulti)\n  \(indentedMulti)\(trimmedTrailing)"
        }

        return action
    }

    /// Render deffakekeys block for layer change notifications.
    /// Creates fake keys that send push-msg when layers are entered/exited,
    /// working around Kanata's limitation where layer-while-held doesn't broadcast LayerChange TCP messages.
    static func renderFakeKeysBlock(_ layers: [RuleCollectionLayer]) -> String {
        guard !layers.isEmpty else { return "" }
        var lines = [
            "#|",
            "================================================================================",
            "VIRTUAL KEYS (deffakekeys)",
            "================================================================================",
            "|#",
            "",
            ";; Used to broadcast layer changes via TCP (layer-while-held doesn't do this natively)",
            "(deffakekeys"
        ]
        // Add enter/exit fake keys for each non-base layer
        for layer in layers {
            let layerName = layer.kanataName
            lines.append("  kp-layer-\(layerName)-enter (push-msg \"layer:\(layerName)\")")
            lines.append("  kp-layer-\(layerName)-exit (push-msg \"layer:base\")")
        }
        lines.append(")")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Render defchordsv2 block for chord mappings (simultaneous key presses)
    static func renderChordsBlock(_ chordMappings: [ChordMapping]) -> String {
        guard !chordMappings.isEmpty else { return "" }
        var lines = [
            "#|",
            "================================================================================",
            "CHORD MAPPINGS (defchordsv2)",
            "================================================================================",
            "|#",
            "",
            "(defchordsv2"
        ]
        for chord in chordMappings {
            // Format: (key1 key2) output timeout release-behavior ()
            // timeout: uses $chord-timeout variable (default 50ms)
            // all-released: trigger when all keys are released
            lines.append("  (\(chord.inputKeys)) \(chord.output) $chord-timeout all-released ()")
        }
        lines.append(")")
        return lines.joined(separator: "\n") + "\n"
    }

    static func renderChordGroupsBlock(_ chordGroups: [ChordGroupConfig]) -> String {
        guard !chordGroups.isEmpty else { return "" }
        var lines = [
            "#|",
            "================================================================================",
            "CHORD GROUPS (defchords) - Preserved from manual config",
            "================================================================================",
            "|#",
            ""
        ]

        for group in chordGroups {
            lines.append("(defchords \(group.name) \(group.timeoutToken))")
            for chord in group.chords {
                let keys = chord.keys.joined(separator: " ")
                lines.append("  (\(keys)) \(chord.action)")
            }
            lines.append(")")
            lines.append("")
        }

        if lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    static func renderSequencesBlock(_ sequences: [KanataDefseqParser.ParsedSequence]) -> String {
        guard !sequences.isEmpty else { return "" }
        var lines = [
            "#|",
            "================================================================================",
            "SEQUENCES (defseq) - Preserved from manual config",
            "================================================================================",
            "|#",
            "",
            "(defseq"
        ]

        for sequence in sequences {
            let keys = "(" + sequence.keys.joined(separator: " ") + ")"
            lines.append("  \(sequence.name) \(keys)")
        }

        lines.append(")")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Render UI-authored chord groups block (MAL-37)
    static func renderUIChordGroupsBlock(_ config: ChordGroupsConfig?) -> String {
        guard let config, !config.groups.isEmpty else { return "" }

        var lines = [
            "#|",
            "================================================================================",
            "CHORD GROUPS (defchords) - UI-Authored",
            "================================================================================",
            "|#",
            ""
        ]

        for group in config.groups {
            // Generate defchords block with timeout
            lines.append("(defchords \(group.name) \(group.timeout))")

            // Add fallback definitions for single keys (they pass through)
            let participatingKeys = group.participatingKeys.sorted()
            for key in participatingKeys {
                lines.append("  (\(key)) \(key)")
            }

            // Add chord definitions
            for chord in group.chords {
                let keys = chord.keys.joined(separator: " ")
                lines.append("  (\(keys)) \(chord.output)")
            }

            lines.append(")")
            lines.append("")
        }

        if lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    static func renderDefsrcBlock(_ blocks: [CollectionBlock]) -> String {
        var lines = [
            "#|",
            "================================================================================",
            "PHYSICAL KEYBOARD LAYOUT - DEFSRC",
            "================================================================================",
            "|#",
            "",
            "(defsrc"
        ]
        if blocks.isEmpty {
            lines.append("  ;; No enabled collections")
        } else {
            for block in blocks {
                lines.append(contentsOf: KeyboardGridFormatter.renderDefsrc(block))
                lines.append("")
            }
            if lines.last == "" { lines.removeLast() }
        }
        lines.append(")")
        return lines.joined(separator: "\n")
    }

    static func renderLayerBlock(
        name: String,
        blocks: [CollectionBlock],
        valueProvider: (LayerEntry) -> String
    ) -> String {
        var lines: [String] = []

        // Add section header for base layer only (other layers are grouped)
        if name == "base" {
            lines.append(contentsOf: [
                "#|",
                "================================================================================",
                "LAYER DEFINITIONS",
                "================================================================================",
                "|#",
                ""
            ])
        }

        lines.append("(deflayer \(name)")
        if blocks.isEmpty {
            lines.append("  ;; No enabled collections")
        } else {
            for block in blocks {
                lines.append(contentsOf: KeyboardGridFormatter.renderLayer(block, valueProvider: valueProvider))
                lines.append("")
            }
            if lines.last == "" { lines.removeLast() }
        }
        lines.append(")")
        return lines.joined(separator: "\n")
    }

    // Note: renderDisabledCollections removed - disabled collections not written to config (ADR-025)

    static func metadataLines(for collection: RuleCollection, indent: String, status: String)
        -> [String]
    {
        [
            "\(indent);; === Collection: \(collection.name) (\(status)) ===",
            "\(indent);; UUID: \(collection.id.uuidString)",
            "\(indent);; Description: \(collection.summary)"
        ]
    }

    static func metadataLines(for activator: MomentaryActivator, indent: String) -> [String] {
        [
            "\(indent);; === Momentary Layer Switch ===",
            "\(indent);; Input: \(activator.input)",
            "\(indent);; Activates: \(activator.targetLayer.displayName)"
        ]
    }
}
