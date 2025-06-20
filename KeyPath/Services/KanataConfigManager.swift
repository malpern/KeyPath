import Foundation

/// Manages Kanata configuration parsing and rule integration
class KanataConfigManager {

    struct KanataConfig {
        var defcfg: String
        var defsrc: [String]
        var deflayer: [String: [String]] // layer_name -> keys
        var additionalSections: [String]

        init() {
            self.defcfg = "process-unmapped-keys yes"
            self.defsrc = ["caps"] // Default minimal setup
            self.deflayer = ["default": ["caps"]]
            self.additionalSections = []
        }
    }

    /// Parses existing kanata configuration
    func parseConfig(_ configText: String) -> KanataConfig {
        var config = KanataConfig()
        let lines = configText.components(separatedBy: .newlines)

        var currentSection: String?
        var sectionContent: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.hasPrefix(";;") || trimmed.isEmpty {
                continue
            }

            // Detect section starts
            if trimmed.hasPrefix("(defcfg") {
                currentSection = "defcfg"
                sectionContent = []
            } else if trimmed.hasPrefix("(defsrc") {
                currentSection = "defsrc"
                sectionContent = []
            } else if trimmed.hasPrefix("(deflayer") {
                // Extract layer name
                let layerName = extractLayerName(from: trimmed) ?? "default"
                currentSection = "deflayer_\(layerName)"
                sectionContent = []
            } else if trimmed == ")" {
                // End of section
                if let section = currentSection {
                    processParsedSection(section, content: sectionContent, config: &config)
                }
                currentSection = nil
                sectionContent = []
            } else if currentSection != nil {
                // Add content to current section
                sectionContent.append(trimmed)
            } else if trimmed.hasPrefix("(defalias") || trimmed.hasPrefix("(defchords") {
                // Handle standalone sections like defalias
                config.additionalSections.append(trimmed)
            }
        }

        return config
    }

    /// Adds a simple key mapping to the configuration
    func addSimpleMapping(_ rule: String, to config: inout KanataConfig) {
        // Parse "a -> b" format
        let components = rule.components(separatedBy: " -> ")
        guard components.count == 2 else {
            // If it's not in simple format, treat it as a complete Kanata rule
            addKanataRule(rule, to: &config)
            return
        }

        let fromKey = components[0].trimmingCharacters(in: .whitespaces)
        let toKey = components[1].trimmingCharacters(in: .whitespaces)

        // Add to defsrc if not already present
        if !config.defsrc.contains(fromKey) {
            config.defsrc.append(fromKey)
        }

        // Update deflayer default
        if var defaultLayer = config.deflayer["default"] {
            // Find the index of fromKey in defsrc
            if let index = config.defsrc.firstIndex(of: fromKey) {
                // Ensure deflayer has enough elements
                while defaultLayer.count <= index {
                    defaultLayer.append("_") // placeholder
                }
                defaultLayer[index] = toKey
                config.deflayer["default"] = defaultLayer
            }
        }
    }

    /// Adds a complete Kanata rule to the configuration
    func addKanataRule(_ rule: String, to config: inout KanataConfig) {
        let cleanRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanRule.isEmpty { return }

        // Check if this is a complete configuration with defsrc and deflayer
        if cleanRule.contains("(defsrc") && cleanRule.contains("(deflayer") {
            // Parse the complete configuration
            let tempConfig = parseConfig(cleanRule)
            
            // Merge defsrc keys
            for key in tempConfig.defsrc {
                if !config.defsrc.contains(key) {
                    config.defsrc.append(key)
                }
            }
            
            // Merge deflayers
            for (layerName, keys) in tempConfig.deflayer {
                if layerName == "default" {
                    // For default layer, we need to merge carefully
                    if var defaultLayer = config.deflayer["default"] {
                        // Ensure we have enough slots
                        while defaultLayer.count < config.defsrc.count {
                            defaultLayer.append("_")
                        }
                        
                        // Update keys based on defsrc positions
                        for (i, srcKey) in tempConfig.defsrc.enumerated() {
                            if let targetIndex = config.defsrc.firstIndex(of: srcKey),
                               i < keys.count {
                                if targetIndex < defaultLayer.count {
                                    defaultLayer[targetIndex] = keys[i]
                                }
                            }
                        }
                        config.deflayer["default"] = defaultLayer
                    }
                } else {
                    // For other layers, just add them
                    config.deflayer[layerName] = keys
                }
            }
            
            // Add any defalias or other sections
            config.additionalSections.append(contentsOf: tempConfig.additionalSections)
            
        } else if cleanRule.hasPrefix("(defalias ") {
            // Parse the defalias to extract the key being remapped
            let components = cleanRule.dropFirst(1).dropLast(1).components(separatedBy: " ")
            if components.count >= 3 && components[0] == "defalias" {
                let sourceKey = components[1]
                let aliasName = sourceKey // Use the source key as the alias name

                // Add the source key to defsrc if not present
                if !config.defsrc.contains(sourceKey) {
                    config.defsrc.append(sourceKey)
                }

                // Update the default layer to use the alias (with @ prefix)
                if var defaultLayer = config.deflayer["default"] {
                    // Find the index of the source key in defsrc
                    if let index = config.defsrc.firstIndex(of: sourceKey) {
                        // Ensure deflayer has enough elements
                        while defaultLayer.count <= index {
                            defaultLayer.append("_") // placeholder
                        }
                        defaultLayer[index] = "@\(aliasName)"
                        config.deflayer["default"] = defaultLayer
                    }
                }

                // Add the defalias to additional sections
                config.additionalSections.append(cleanRule)
            }
        } else {
            // For non-defalias rules, just add them as additional sections
            config.additionalSections.append(cleanRule)
        }
    }

    /// Generates complete kanata configuration text
    func generateConfig(_ config: KanataConfig) -> String {
        var result = """
        ;; KeyPath Generated Kanata Configuration
        ;; This file was automatically created by KeyPath

        (defcfg
          \(config.defcfg)
        )

        (defsrc
          \(config.defsrc.joined(separator: " "))
        )

        """

        // Add deflayers
        for (layerName, keys) in config.deflayer {
            result += """
            (deflayer \(layerName)
              \(keys.joined(separator: " "))
            )

            """
        }

        // Add additional sections
        for section in config.additionalSections {
            result += section + "\n\n"
        }

        result += ";; KeyPath rules will be added below\n"

        return result
    }

    // MARK: - Private Helper Methods

    private func extractLayerName(from line: String) -> String? {
        // Extract layer name from "(deflayer layer_name"
        let pattern = #"\(deflayer\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            if let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
        return nil
    }

    private func processParsedSection(_ section: String, content: [String], config: inout KanataConfig) {
        switch section {
        case "defcfg":
            config.defcfg = content.joined(separator: "\n  ")
        case "defsrc":
            config.defsrc = content.joined(separator: " ").components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
        case let section where section.hasPrefix("deflayer_"):
            let layerName = String(section.dropFirst("deflayer_".count))
            let keys = content.joined(separator: " ").components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            config.deflayer[layerName] = keys
        default:
            break
        }
    }
}
