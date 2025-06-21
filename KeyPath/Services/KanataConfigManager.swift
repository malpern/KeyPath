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
        print("🐛 DEBUG: KanataConfigManager.parseConfig called")
        print("🐛 DEBUG: Config text length: \(configText.count)")
        
        var config = KanataConfig()
        print("🐛 DEBUG: Initial config - defsrc: \(config.defsrc), deflayer: \(config.deflayer)")
        
        let lines = configText.components(separatedBy: .newlines)
        print("🐛 DEBUG: Config has \(lines.count) lines")

        var currentSection: String?
        var sectionContent: [String] = []

        for (lineNumber, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.hasPrefix(";;") || trimmed.isEmpty {
                continue
            }

            print("🐛 DEBUG: Line \(lineNumber): '\(trimmed)'")

            // Detect section starts
            if trimmed.hasPrefix("(defcfg") {
                print("🐛 DEBUG: Found defcfg section")
                currentSection = "defcfg"
                sectionContent = []
            } else if trimmed.hasPrefix("(defsrc") {
                print("🐛 DEBUG: Found defsrc section")
                currentSection = "defsrc"
                sectionContent = []
            } else if trimmed.hasPrefix("(deflayer") {
                // Extract layer name
                let layerName = extractLayerName(from: trimmed) ?? "default"
                print("🐛 DEBUG: Found deflayer section: '\(layerName)'")
                currentSection = "deflayer_\(layerName)"
                sectionContent = []
            } else if trimmed == ")" {
                // End of section
                print("🐛 DEBUG: End of section, currentSection: \(currentSection ?? "nil")")
                if let section = currentSection {
                    print("🐛 DEBUG: Processing section '\(section)' with content: \(sectionContent)")
                    processParsedSection(section, content: sectionContent, config: &config)
                    print("🐛 DEBUG: After processing section - defsrc: \(config.defsrc), deflayer: \(config.deflayer)")
                }
                currentSection = nil
                sectionContent = []
            } else if currentSection != nil {
                // Add content to current section
                print("🐛 DEBUG: Adding to section '\(currentSection!)': '\(trimmed)'")
                sectionContent.append(trimmed)
            } else if trimmed.hasPrefix("(defalias") || trimmed.hasPrefix("(defchords") {
                // Handle standalone sections like defalias
                print("🐛 DEBUG: Found standalone section: '\(trimmed)'")
                config.additionalSections.append(trimmed)
            }
        }

        print("🐛 DEBUG: Final parsed config:")
        print("🐛 DEBUG: - defsrc: \(config.defsrc)")
        print("🐛 DEBUG: - deflayer keys: \(config.deflayer.keys)")
        print("🐛 DEBUG: - deflayer['default']: \(config.deflayer["default"] ?? [])")
        print("🐛 DEBUG: - additionalSections: \(config.additionalSections)")
        
        return config
    }

    /// Adds a simple key mapping to the configuration
    func addSimpleMapping(_ rule: String, to config: inout KanataConfig) {
        print("🐛 DEBUG: KanataConfigManager.addSimpleMapping called with rule: '\(rule)'")
        
        // Parse "a -> b" format
        let components = rule.components(separatedBy: " -> ")
        print("🐛 DEBUG: Rule components: \(components)")
        print("🐛 DEBUG: Components count: \(components.count)")
        
        guard components.count == 2 else {
            print("🐛 DEBUG: Not in simple format, delegating to addKanataRule")
            // If it's not in simple format, treat it as a complete Kanata rule
            addKanataRule(rule, to: &config)
            return
        }

        let fromKey = components[0].trimmingCharacters(in: .whitespaces)
        let toKey = components[1].trimmingCharacters(in: .whitespaces)
        print("🐛 DEBUG: fromKey: '\(fromKey)', toKey: '\(toKey)'")
        print("🐛 DEBUG: Current defsrc before adding: \(config.defsrc)")

        // Add to defsrc if not already present
        if !config.defsrc.contains(fromKey) {
            print("🐛 DEBUG: Adding '\(fromKey)' to defsrc")
            config.defsrc.append(fromKey)
        } else {
            print("🐛 DEBUG: '\(fromKey)' already exists in defsrc")
        }
        print("🐛 DEBUG: Current defsrc after adding: \(config.defsrc)")

        // Update deflayer default
        print("🐛 DEBUG: Current deflayer keys: \(config.deflayer.keys)")
        if var defaultLayer = config.deflayer["default"] {
            print("🐛 DEBUG: Current defaultLayer before update: \(defaultLayer)")
            
            // Find the index of fromKey in defsrc
            if let index = config.defsrc.firstIndex(of: fromKey) {
                print("🐛 DEBUG: Found '\(fromKey)' at index \(index) in defsrc")
                
                // Ensure deflayer has enough elements
                while defaultLayer.count <= index {
                    print("🐛 DEBUG: Expanding defaultLayer with placeholder (current size: \(defaultLayer.count), needed: \(index + 1))")
                    defaultLayer.append("_") // placeholder
                }
                print("🐛 DEBUG: defaultLayer after expansion: \(defaultLayer)")
                
                print("🐛 DEBUG: Setting defaultLayer[\(index)] = '\(toKey)'")
                defaultLayer[index] = toKey
                config.deflayer["default"] = defaultLayer
                print("🐛 DEBUG: Updated defaultLayer: \(defaultLayer)")
            } else {
                print("🐛 DEBUG: ERROR: Could not find '\(fromKey)' in defsrc after adding it!")
            }
        } else {
            print("🐛 DEBUG: ERROR: No 'default' layer found in deflayer!")
            print("🐛 DEBUG: Available layers: \(config.deflayer.keys)")
        }
        
        print("🐛 DEBUG: Final config state:")
        print("🐛 DEBUG: - defsrc: \(config.defsrc)")
        print("🐛 DEBUG: - deflayer['default']: \(config.deflayer["default"] ?? [])")
    }

    /// Adds a complete Kanata rule to the configuration
    func addKanataRule(_ rule: String, to config: inout KanataConfig) {
        print("🐛 DEBUG: KanataConfigManager.addKanataRule called with rule: '\(rule)'")
        let cleanRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🐛 DEBUG: cleanRule: '\(cleanRule)'")
        if cleanRule.isEmpty { 
            print("🐛 DEBUG: cleanRule is empty, returning")
            return 
        }

        // Check if this is a complete configuration with defsrc and deflayer
        if cleanRule.contains("(defsrc") && cleanRule.contains("(deflayer") {
            print("🐛 DEBUG: Rule contains complete configuration with defsrc and deflayer")
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
            print("🐛 DEBUG: Rule is a defalias")
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
            print("🐛 DEBUG: Rule doesn't match any known pattern, adding as additional section")
            // For non-defalias rules, just add them as additional sections
            config.additionalSections.append(cleanRule)
        }
    }

    /// Generates complete kanata configuration text
    func generateConfig(_ config: KanataConfig) -> String {
        print("🐛 DEBUG: KanataConfigManager.generateConfig called")
        print("🐛 DEBUG: Input config - defsrc: \(config.defsrc)")
        print("🐛 DEBUG: Input config - deflayer keys: \(config.deflayer.keys)")
        print("🐛 DEBUG: Input config - deflayer['default']: \(config.deflayer["default"] ?? [])")
        
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
            print("🐛 DEBUG: Adding deflayer '\(layerName)' with keys: \(keys)")
            result += """
            (deflayer \(layerName)
              \(keys.joined(separator: " "))
            )

            """
        }

        // Add additional sections
        for section in config.additionalSections {
            print("🐛 DEBUG: Adding additional section: \(section)")
            result += section + "\n\n"
        }

        result += ";; KeyPath rules will be added below\n"

        print("🐛 DEBUG: Generated config length: \(result.count)")
        print("🐛 DEBUG: Generated config contains '5': \(result.contains("5"))")
        print("🐛 DEBUG: Generated config contains '6': \(result.contains("6"))")
        
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
        print("🐛 DEBUG: processParsedSection called for section: '\(section)'")
        print("🐛 DEBUG: Section content: \(content)")
        
        switch section {
        case "defcfg":
            print("🐛 DEBUG: Processing defcfg section")
            config.defcfg = content.joined(separator: "\n  ")
            print("🐛 DEBUG: Updated defcfg: \(config.defcfg)")
        case "defsrc":
            print("🐛 DEBUG: Processing defsrc section")
            let joinedContent = content.joined(separator: " ")
            print("🐛 DEBUG: Joined defsrc content: '\(joinedContent)'")
            config.defsrc = joinedContent.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            print("🐛 DEBUG: Updated defsrc: \(config.defsrc)")
        case let section where section.hasPrefix("deflayer_"):
            let layerName = String(section.dropFirst("deflayer_".count))
            print("🐛 DEBUG: Processing deflayer section: '\(layerName)'")
            let joinedContent = content.joined(separator: " ")
            print("🐛 DEBUG: Joined deflayer content: '\(joinedContent)'")
            let keys = joinedContent.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            print("🐛 DEBUG: Parsed deflayer keys: \(keys)")
            config.deflayer[layerName] = keys
            print("🐛 DEBUG: Updated deflayer[\(layerName)]: \(config.deflayer[layerName] ?? [])")
        default:
            print("🐛 DEBUG: Unknown section type: '\(section)'")
            break
        }
    }
}
