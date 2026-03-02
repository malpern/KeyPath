import Foundation
import KeyPathCore

// MARK: - Conversion Result

/// The output of a Karabiner → KeyPath conversion.
struct KarabinerConversionResult: Sendable {
    let collections: [RuleCollection]
    let appKeymaps: [AppKeymap]
    let launcherMappings: [LauncherMapping]
    let skippedRules: [KarabinerSkippedRule]
    let warnings: [String]
    let profileName: String
}

/// A rule that was skipped during conversion, with reason.
struct KarabinerSkippedRule: Identifiable, Sendable {
    let id = UUID()
    let description: String
    let reason: String
}

// MARK: - Error Type

enum KarabinerImportError: LocalizedError {
    case fileNotFound
    case invalidJSON(String)
    case noProfiles
    case fileTooLarge
    case profileIndexOutOfRange(Int)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            "Karabiner configuration file not found"
        case let .invalidJSON(detail):
            "Invalid Karabiner JSON: \(detail)"
        case .noProfiles:
            "No profiles found in Karabiner configuration"
        case .fileTooLarge:
            "Configuration file is too large (max 10 MB)"
        case let .profileIndexOutOfRange(index):
            "Profile index \(index) is out of range"
        }
    }
}

// MARK: - Converter Service

/// Converts Karabiner-Elements JSON configurations into KeyPath rule collections.
///
/// Usage:
/// ```swift
/// let service = KarabinerConverterService()
/// let profiles = try service.getProfiles(from: data)
/// let result = try service.convert(data: data, profileIndex: 0)
/// ```
struct KarabinerConverterService: Sendable {
    /// Maximum file size we'll accept (10 MB).
    private static let maxFileSize = 10 * 1024 * 1024

    // MARK: - Public API

    /// List available profiles in a Karabiner config file.
    func getProfiles(from data: Data) throws -> [(name: String, index: Int, isSelected: Bool)] {
        let config = try decodeConfig(data)
        return config.profiles.enumerated().map { index, profile in
            (name: profile.name, index: index, isSelected: profile.selected ?? false)
        }
    }

    /// Convert a Karabiner JSON config into KeyPath rule collections.
    /// - Parameters:
    ///   - data: Raw JSON data from karabiner.json
    ///   - profileIndex: Which profile to convert (nil = first selected, or first profile)
    func convert(data: Data, profileIndex: Int?) throws -> KarabinerConversionResult {
        let config = try decodeConfig(data)
        guard !config.profiles.isEmpty else {
            throw KarabinerImportError.noProfiles
        }

        let profileIdx: Int
        if let idx = profileIndex {
            guard idx >= 0, idx < config.profiles.count else {
                throw KarabinerImportError.profileIndexOutOfRange(idx)
            }
            profileIdx = idx
        } else {
            profileIdx = config.profiles.firstIndex(where: { $0.selected == true }) ?? 0
        }

        let profile = config.profiles[profileIdx]
        return convertProfile(profile)
    }

    // MARK: - Decoding

    private func decodeConfig(_ data: Data) throws -> KarabinerConfig {
        guard data.count <= Self.maxFileSize else {
            throw KarabinerImportError.fileTooLarge
        }
        do {
            return try JSONDecoder().decode(KarabinerConfig.self, from: data)
        } catch {
            throw KarabinerImportError.invalidJSON(error.localizedDescription)
        }
    }

    // MARK: - Profile Conversion

    private func convertProfile(_ profile: KarabinerProfile) -> KarabinerConversionResult {
        var collections: [RuleCollection] = []
        var appKeymaps: [AppKeymap] = []
        var launcherMappings: [LauncherMapping] = []
        var skipped: [KarabinerSkippedRule] = []
        var warnings: [String] = []

        // 1. Convert simple modifications
        if let simpleMods = profile.simpleModifications, !simpleMods.isEmpty {
            let mappings = convertSimpleModifications(simpleMods, skipped: &skipped)
            if !mappings.isEmpty {
                let collection = RuleCollection(
                    name: "Karabiner Simple Remaps",
                    summary: "Imported from Karabiner simple modifications",
                    category: .custom,
                    mappings: mappings,
                    icon: "arrow.right.arrow.left",
                    tags: ["karabiner", "imported"]
                )
                collections.append(collection)
            }
        }

        // 2. Convert complex modifications
        if let complexMods = profile.complexModifications, let rules = complexMods.rules {
            for rule in rules {
                if rule.enabled == false { continue }

                let ruleResult = convertRule(rule)

                if !ruleResult.mappings.isEmpty {
                    let collection = RuleCollection(
                        name: ruleResult.name,
                        summary: ruleResult.summary,
                        category: .custom,
                        mappings: ruleResult.mappings,
                        icon: ruleResult.icon,
                        tags: ["karabiner", "imported"]
                    )
                    collections.append(collection)
                }

                appKeymaps.append(contentsOf: ruleResult.appKeymaps)
                launcherMappings.append(contentsOf: ruleResult.launcherMappings)
                skipped.append(contentsOf: ruleResult.skipped)
                warnings.append(contentsOf: ruleResult.warnings)
            }
        }

        // Deduplicate app keymaps by bundle identifier
        appKeymaps = deduplicateAppKeymaps(appKeymaps)

        return KarabinerConversionResult(
            collections: collections,
            appKeymaps: appKeymaps,
            launcherMappings: launcherMappings,
            skippedRules: skipped,
            warnings: warnings,
            profileName: profile.name
        )
    }

    // MARK: - Simple Modifications

    private func convertSimpleModifications(
        _ mods: [KarabinerSimpleModification],
        skipped: inout [KarabinerSkippedRule]
    ) -> [KeyMapping] {
        var mappings: [KeyMapping] = []

        for mod in mods {
            let fromKey = mod.from.keyCode ?? mod.from.consumerKeyCode
            let toKey = mod.to.first?.keyCode ?? mod.to.first?.consumerKeyCode

            guard let fromKey, let toKey else {
                let desc = "Simple: \(mod.from.keyCode ?? mod.from.consumerKeyCode ?? "unknown") → \(mod.to.first?.keyCode ?? "unknown")"
                skipped.append(KarabinerSkippedRule(description: desc, reason: "Unsupported key type (pointing button or unknown)"))
                continue
            }

            let kanataFrom: String?
            let kanataTo: String?

            if mod.from.keyCode != nil {
                kanataFrom = KarabinerKeyTranslator.toKanata(fromKey)
            } else {
                kanataFrom = KarabinerKeyTranslator.consumerKeyToKanata(fromKey)
            }

            if mod.to.first?.keyCode != nil {
                kanataTo = KarabinerKeyTranslator.toKanata(toKey)
            } else {
                kanataTo = KarabinerKeyTranslator.consumerKeyToKanata(toKey)
            }

            guard let input = kanataFrom, let output = kanataTo else {
                skipped.append(KarabinerSkippedRule(
                    description: "Simple: \(fromKey) → \(toKey)",
                    reason: "Unknown key code"
                ))
                continue
            }

            mappings.append(KeyMapping(
                input: input,
                output: output,
                description: "\(fromKey) → \(toKey)"
            ))
        }

        return mappings
    }

    // MARK: - Rule Conversion

    private struct RuleConversionResult {
        var name: String
        var summary: String
        var icon: String
        var mappings: [KeyMapping] = []
        var appKeymaps: [AppKeymap] = []
        var launcherMappings: [LauncherMapping] = []
        var skipped: [KarabinerSkippedRule] = []
        var warnings: [String] = []
    }

    private func convertRule(_ rule: KarabinerRule) -> RuleConversionResult {
        let description = rule.description ?? "Untitled Rule"
        var result = RuleConversionResult(
            name: description,
            summary: "Imported from Karabiner: \(description)",
            icon: "keyboard"
        )

        guard let manipulators = rule.manipulators else { return result }

        // Detect variable-based layers (set_variable / variable_if patterns)
        let layerVariables = detectLayerVariables(in: manipulators)

        for manipulator in manipulators {
            convertManipulator(manipulator, rule: description, layerVariables: layerVariables, result: &result)
        }

        // Choose icon based on content
        if !result.appKeymaps.isEmpty {
            result.icon = "app.badge"
        } else if !result.launcherMappings.isEmpty {
            result.icon = "arrow.up.forward.app"
        } else if result.mappings.contains(where: { $0.behavior != nil }) {
            result.icon = "rectangle.on.rectangle"
        }

        return result
    }

    // MARK: - Manipulator Classification & Conversion

    private func convertManipulator(
        _ manipulator: KarabinerManipulator,
        rule: String,
        layerVariables: Set<String>,
        result: inout RuleConversionResult
    ) {
        guard manipulator.type == "basic" || manipulator.type == nil else {
            result.skipped.append(KarabinerSkippedRule(
                description: rule,
                reason: "Unsupported manipulator type: \(manipulator.type ?? "unknown")"
            ))
            return
        }

        // Check for unsupported features
        if manipulator.from?.pointingButton != nil {
            result.skipped.append(KarabinerSkippedRule(
                description: rule,
                reason: "Mouse button remapping not supported"
            ))
            return
        }

        if manipulator.to?.contains(where: { $0.mouseKey != nil }) == true {
            result.skipped.append(KarabinerSkippedRule(
                description: rule,
                reason: "Mouse key emulation not supported"
            ))
            return
        }

        if manipulator.to?.contains(where: { $0.selectInputSource != nil }) == true {
            result.skipped.append(KarabinerSkippedRule(
                description: rule,
                reason: "Input source switching not supported"
            ))
            return
        }

        // Extract app conditions
        let appConditions = extractAppConditions(from: manipulator.conditions)
        let variableConditions = extractVariableConditions(from: manipulator.conditions)

        // Skip variable-only activation manipulators (these set up layers, not actual mappings)
        if isVariableActivator(manipulator, layerVariables: layerVariables) {
            return
        }

        // Skip manipulators guarded by variable conditions — KeyPath can't gate rules
        // on variable state, so importing them unconditionally would change behavior
        if !variableConditions.isEmpty {
            let varNames = variableConditions.map(\.name).joined(separator: ", ")
            result.skipped.append(KarabinerSkippedRule(
                description: rule,
                reason: "Guarded by variable condition (\(varNames)) — layer-gated rules not yet supported"
            ))
            return
        }

        // Classify and convert
        let classification = classifyManipulator(manipulator)

        switch classification {
        case .shellCommand:
            convertShellCommand(manipulator, rule: rule, appConditions: appConditions, result: &result)

        case .dualRole:
            convertDualRole(manipulator, rule: rule, appConditions: appConditions, result: &result)

        case .chord:
            convertChord(manipulator, rule: rule, appConditions: appConditions, result: &result)

        case .macro:
            convertMacro(manipulator, rule: rule, appConditions: appConditions, result: &result)

        case .simpleRemap:
            convertSimpleRemap(manipulator, rule: rule, appConditions: appConditions, result: &result)

        case .unsupported(let reason):
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: reason))
        }
    }

    // MARK: - Classification

    private enum ManipulatorClassification {
        case simpleRemap
        case dualRole
        case chord
        case macro
        case shellCommand
        case unsupported(String)
    }

    private func classifyManipulator(_ manipulator: KarabinerManipulator) -> ManipulatorClassification {
        // Shell command
        if manipulator.to?.contains(where: { $0.shellCommand != nil }) == true {
            return .shellCommand
        }

        // Chord (simultaneous keys)
        if manipulator.from?.simultaneous != nil {
            return .chord
        }

        // Dual-role (to + to_if_alone)
        if manipulator.toIfAlone != nil, manipulator.to != nil {
            return .dualRole
        }

        // Multi-key sequence (macro)
        if let toArray = manipulator.to, toArray.count > 1,
           toArray.allSatisfy({ $0.keyCode != nil || $0.consumerKeyCode != nil })
        {
            return .macro
        }

        // Variable set (layer toggle via variable)
        if manipulator.to?.contains(where: { $0.setVariable != nil }) == true {
            // If the only "to" action is setting a variable, this is a layer activator
            if manipulator.to?.allSatisfy({ $0.setVariable != nil || $0.keyCode == nil && $0.consumerKeyCode == nil && $0.shellCommand == nil }) == true {
                return .simpleRemap // Will be handled as a layer toggle
            }
        }

        // Simple remap
        if manipulator.from != nil, manipulator.to != nil {
            return .simpleRemap
        }

        return .unsupported("No recognized from/to mapping")
    }

    // MARK: - Simple Remap Conversion

    private func convertSimpleRemap(
        _ manipulator: KarabinerManipulator,
        rule: String,
        appConditions: [AppCondition],
        result: inout RuleConversionResult
    ) {
        guard let from = manipulator.from,
              let toFirst = manipulator.to?.first
        else { return }

        // Handle variable set (layer toggle)
        if let setVar = toFirst.setVariable {
            // This sets a variable — treat as a remap that doesn't produce a key
            result.warnings.append("Variable '\(setVar.name)' toggle in '\(rule)' — layer variables are informational only")
            return
        }

        let fromKey = from.keyCode ?? from.consumerKeyCode
        guard let fromKey else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Missing from key"))
            return
        }

        let toKey = toFirst.keyCode ?? toFirst.consumerKeyCode
        guard let toKey else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Missing to key"))
            return
        }

        // Translate keys
        let mandatoryMods = from.modifiers?.mandatory ?? []
        let toMods = toFirst.modifiers ?? []

        // Warn about unsupported modifier prefixes (e.g., fn)
        let droppedFromMods = mandatoryMods.filter { KarabinerKeyTranslator.unsupportedModifierPrefixes.contains($0) }
        let droppedToMods = toMods.filter { KarabinerKeyTranslator.unsupportedModifierPrefixes.contains($0) }
        if !droppedFromMods.isEmpty || !droppedToMods.isEmpty {
            let dropped = (droppedFromMods + droppedToMods).joined(separator: ", ")
            result.warnings.append("'\(rule)': modifier '\(dropped)' has no Kanata prefix equivalent and was dropped from the key expression")
        }

        let kanataInput: String?
        if from.keyCode != nil {
            kanataInput = KarabinerKeyTranslator.toKanataExpression(keyCode: fromKey, modifiers: mandatoryMods)
        } else {
            kanataInput = KarabinerKeyTranslator.consumerKeyToKanataExpression(keyCode: fromKey, modifiers: mandatoryMods)
        }

        let kanataOutput: String?
        if toFirst.keyCode != nil {
            kanataOutput = KarabinerKeyTranslator.toKanataExpression(keyCode: toKey, modifiers: toMods)
        } else {
            kanataOutput = KarabinerKeyTranslator.consumerKeyToKanataExpression(keyCode: toKey, modifiers: toMods)
        }

        guard let input = kanataInput, let output = kanataOutput else {
            result.skipped.append(KarabinerSkippedRule(
                description: rule,
                reason: "Unknown key: \(fromKey) or \(toKey)"
            ))
            return
        }

        let mapping = KeyMapping(
            input: input,
            output: output,
            description: "\(fromKey) → \(toKey)"
        )

        routeMapping(mapping, appConditions: appConditions, rule: rule, result: &result)
    }

    // MARK: - Dual Role Conversion

    private func convertDualRole(
        _ manipulator: KarabinerManipulator,
        rule: String,
        appConditions: [AppCondition],
        result: inout RuleConversionResult
    ) {
        guard let from = manipulator.from,
              let toFirst = manipulator.to?.first,
              let aloneFirst = manipulator.toIfAlone?.first
        else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Incomplete dual-role definition"))
            return
        }

        let fromKey = from.keyCode ?? from.consumerKeyCode
        guard let fromKey else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Missing from key in dual-role"))
            return
        }

        let kanataFrom: String?
        if from.keyCode != nil {
            kanataFrom = KarabinerKeyTranslator.toKanata(fromKey)
        } else {
            kanataFrom = KarabinerKeyTranslator.consumerKeyToKanata(fromKey)
        }

        guard let input = kanataFrom else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Unknown from key: \(fromKey)"))
            return
        }

        // Tap action (to_if_alone)
        let tapKey = aloneFirst.keyCode ?? aloneFirst.consumerKeyCode ?? ""
        let tapMods = aloneFirst.modifiers ?? []
        let tapAction: String
        if let key = aloneFirst.keyCode {
            tapAction = KarabinerKeyTranslator.toKanataExpression(keyCode: key, modifiers: tapMods) ?? key
        } else if let key = aloneFirst.consumerKeyCode {
            tapAction = KarabinerKeyTranslator.consumerKeyToKanataExpression(keyCode: key, modifiers: tapMods) ?? key
        } else {
            tapAction = tapKey
        }

        // Hold action (to)
        let holdKey = toFirst.keyCode ?? toFirst.consumerKeyCode ?? ""
        let holdMods = toFirst.modifiers ?? []
        let holdAction: String
        if let key = toFirst.keyCode {
            holdAction = KarabinerKeyTranslator.toKanataExpression(keyCode: key, modifiers: holdMods) ?? key
        } else if let key = toFirst.consumerKeyCode {
            holdAction = KarabinerKeyTranslator.consumerKeyToKanataExpression(keyCode: key, modifiers: holdMods) ?? key
        } else if holdMods.count == 1, let mod = KarabinerKeyTranslator.modifierToKanata(holdMods[0]) {
            holdAction = mod
        } else {
            holdAction = holdKey
        }

        guard !tapAction.isEmpty, !holdAction.isEmpty else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Could not translate dual-role actions"))
            return
        }

        let timeout = manipulator.parameters?.basicToIfAloneTimeoutMilliseconds ?? 200

        let behavior = MappingBehavior.dualRole(DualRoleBehavior(
            tapAction: tapAction,
            holdAction: holdAction,
            tapTimeout: timeout,
            holdTimeout: timeout,
            activateHoldOnOtherKey: true
        ))

        let mapping = KeyMapping(
            input: input,
            output: holdAction,
            description: "Tap: \(tapAction), Hold: \(holdAction)",
            behavior: behavior
        )

        routeMapping(mapping, appConditions: appConditions, rule: rule, result: &result)
    }

    // MARK: - Chord Conversion

    private func convertChord(
        _ manipulator: KarabinerManipulator,
        rule: String,
        appConditions: [AppCondition],
        result: inout RuleConversionResult
    ) {
        guard let from = manipulator.from,
              let simultaneous = from.simultaneous,
              !simultaneous.isEmpty,
              let toFirst = manipulator.to?.first
        else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Incomplete chord definition"))
            return
        }

        // Translate chord keys
        var chordKeys: [String] = []
        for simKey in simultaneous {
            if let keyCode = simKey.keyCode, let kanata = KarabinerKeyTranslator.toKanata(keyCode) {
                chordKeys.append(kanata)
            } else if let consumerKey = simKey.consumerKeyCode, let kanata = KarabinerKeyTranslator.consumerKeyToKanata(consumerKey) {
                chordKeys.append(kanata)
            } else {
                result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Unknown chord key"))
                return
            }
        }

        // Also include the from key itself
        if let fromKey = from.keyCode, let kanata = KarabinerKeyTranslator.toKanata(fromKey) {
            if !chordKeys.contains(kanata) {
                chordKeys.insert(kanata, at: 0)
            }
        }

        guard chordKeys.count >= 2 else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Chord needs at least 2 keys"))
            return
        }

        // Translate output
        let toMods = toFirst.modifiers ?? []
        let output: String
        if let key = toFirst.keyCode {
            output = KarabinerKeyTranslator.toKanataExpression(keyCode: key, modifiers: toMods) ?? key
        } else if let key = toFirst.consumerKeyCode {
            output = KarabinerKeyTranslator.consumerKeyToKanataExpression(keyCode: key, modifiers: toMods) ?? key
        } else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "No output for chord"))
            return
        }

        let timeout = manipulator.parameters?.basicSimultaneousThresholdMilliseconds ?? 200

        let behavior = MappingBehavior.chord(ChordBehavior(
            keys: chordKeys,
            output: output,
            timeout: max(50, timeout),
            description: rule
        ))

        let mapping = KeyMapping(
            input: chordKeys.first ?? "",
            output: output,
            description: "Chord: \(chordKeys.joined(separator: "+")) → \(output)",
            behavior: behavior
        )

        routeMapping(mapping, appConditions: appConditions, rule: rule, result: &result)
    }

    // MARK: - Macro Conversion

    private func convertMacro(
        _ manipulator: KarabinerManipulator,
        rule: String,
        appConditions: [AppCondition],
        result: inout RuleConversionResult
    ) {
        guard let from = manipulator.from,
              let toArray = manipulator.to, toArray.count > 1
        else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Incomplete macro definition"))
            return
        }

        let fromKey = from.keyCode ?? from.consumerKeyCode
        guard let fromKey else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Missing from key in macro"))
            return
        }

        let mandatoryMods = from.modifiers?.mandatory ?? []
        let kanataInput: String?
        if from.keyCode != nil {
            kanataInput = KarabinerKeyTranslator.toKanataExpression(keyCode: fromKey, modifiers: mandatoryMods)
        } else {
            kanataInput = KarabinerKeyTranslator.consumerKeyToKanataExpression(keyCode: fromKey, modifiers: mandatoryMods)
        }

        guard let input = kanataInput else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Unknown from key: \(fromKey)"))
            return
        }

        // Translate each output key
        var outputs: [String] = []
        var droppedKeyCount = 0
        for to in toArray {
            if let key = to.keyCode {
                if let kanata = KarabinerKeyTranslator.toKanataExpression(keyCode: key, modifiers: to.modifiers ?? []) {
                    outputs.append(kanata)
                } else {
                    droppedKeyCount += 1
                }
            } else if let key = to.consumerKeyCode {
                if let kanata = KarabinerKeyTranslator.consumerKeyToKanataExpression(keyCode: key, modifiers: to.modifiers ?? []) {
                    outputs.append(kanata)
                } else {
                    droppedKeyCount += 1
                }
            }
        }

        guard !outputs.isEmpty else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "No translatable output keys in macro"))
            return
        }

        if droppedKeyCount > 0 {
            result.warnings.append("'\(rule)': \(droppedKeyCount) key(s) in macro sequence could not be translated and were dropped")
        }

        let behavior = MappingBehavior.macro(MacroBehavior(
            outputs: outputs,
            description: rule,
            source: .keys
        ))

        let mapping = KeyMapping(
            input: input,
            output: outputs.first ?? "",
            description: "Macro: \(outputs.joined(separator: " "))",
            behavior: behavior
        )

        routeMapping(mapping, appConditions: appConditions, rule: rule, result: &result)
    }

    // MARK: - Shell Command Conversion

    private func convertShellCommand(
        _ manipulator: KarabinerManipulator,
        rule: String,
        appConditions: [AppCondition],
        result: inout RuleConversionResult
    ) {
        guard let from = manipulator.from,
              let shellCmd = manipulator.to?.first(where: { $0.shellCommand != nil })?.shellCommand
        else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Incomplete shell command"))
            return
        }

        let fromKey = from.keyCode ?? from.consumerKeyCode
        guard let fromKey else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Missing trigger key for shell command"))
            return
        }

        let mandatoryMods = from.modifiers?.mandatory ?? []
        let kanataInput: String?
        if from.keyCode != nil {
            kanataInput = KarabinerKeyTranslator.toKanataExpression(keyCode: fromKey, modifiers: mandatoryMods)
        } else {
            kanataInput = KarabinerKeyTranslator.consumerKeyToKanataExpression(keyCode: fromKey, modifiers: mandatoryMods)
        }

        guard let input = kanataInput else {
            result.skipped.append(KarabinerSkippedRule(description: rule, reason: "Unknown trigger key: \(fromKey)"))
            return
        }

        // Parse shell command to detect app launches and URL opens
        let target = parseShellCommand(shellCmd)

        let launcherMapping = LauncherMapping(
            key: input,
            target: target
        )
        result.launcherMappings.append(launcherMapping)
    }

    /// Parse a shell command string to detect `open -a "App"`, `open "URL"`, or raw scripts.
    private func parseShellCommand(_ cmd: String) -> LauncherTarget {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)

        // Detect: open -a "AppName" or open -a AppName
        if let captured = captureGroup(in: trimmed, pattern: #"^open\s+-a\s+[\"']?([^\"']+?)[\"']?\s*$"#) {
            return .app(name: captured, bundleId: nil)
        }

        // Detect: open "https://..." or open https://...
        if let captured = captureGroup(in: trimmed, pattern: #"^open\s+[\"']?(https?://[^\s\"']+)[\"']?\s*$"#) {
            return .url(captured)
        }

        // Detect: open /path/to/folder or open ~/folder
        if let captured = captureGroup(in: trimmed, pattern: #"^open\s+[\"']?([~/][^\s\"']+)[\"']?\s*$"#) {
            return .folder(path: captured, name: nil)
        }

        // Generic script
        return .script(path: trimmed, name: nil)
    }

    /// Extract the first capture group from a regex match.
    private func captureGroup(in string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: string)
        else { return nil }
        return String(string[captureRange]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - App Condition Helpers

    private struct AppCondition {
        let bundleIdentifiers: [String]
        let isIf: Bool // true = frontmost_application_if, false = _unless
    }

    private func extractAppConditions(from conditions: [KarabinerCondition]?) -> [AppCondition] {
        guard let conditions else { return [] }
        return conditions.compactMap { condition in
            guard condition.type == "frontmost_application_if" || condition.type == "frontmost_application_unless",
                  let bundleIds = condition.bundleIdentifiers, !bundleIds.isEmpty
            else { return nil }
            return AppCondition(
                bundleIdentifiers: bundleIds,
                isIf: condition.type == "frontmost_application_if"
            )
        }
    }

    private func extractVariableConditions(from conditions: [KarabinerCondition]?) -> [(name: String, value: KarabinerVariableValue)] {
        guard let conditions else { return [] }
        return conditions.compactMap { condition in
            guard condition.type == "variable_if" || condition.type == "variable_unless",
                  let name = condition.name, let value = condition.value
            else { return nil }
            return (name: name, value: value)
        }
    }

    /// Route a mapping to app keymaps or global mappings based on app conditions.
    /// Handles `_if` conditions as app-specific overrides, and `_unless` conditions
    /// as global mappings with a warning (since KeyPath can't express "except in app X").
    private func routeMapping(
        _ mapping: KeyMapping,
        appConditions: [AppCondition],
        rule: String,
        result: inout RuleConversionResult
    ) {
        let ifConditions = appConditions.filter(\.isIf)
        let unlessConditions = appConditions.filter { !$0.isIf }

        if !ifConditions.isEmpty {
            // Add as app-specific overrides
            for condition in ifConditions {
                for bundleId in condition.bundleIdentifiers {
                    // Strip regex anchors and escapes for bundle ID
                    let cleanBundleId = bundleId
                        .replacingOccurrences(of: "^", with: "")
                        .replacingOccurrences(of: "$", with: "")
                        .replacingOccurrences(of: "\\.", with: ".")

                    // Skip bundle IDs that still contain regex metacharacters after cleanup
                    // (e.g., "com.google.(Chrome|Chromium)" from "^com\.google\.(Chrome|Chromium)$")
                    if cleanBundleId.contains(where: { "*+?[]|(){}\\".contains($0) }) {
                        result.skipped.append(KarabinerSkippedRule(
                            description: rule,
                            reason: "App condition uses regex pattern '\(bundleId)' — only literal bundle IDs are supported"
                        ))
                        continue
                    }

                    let override = AppKeyOverride(
                        inputKey: mapping.input,
                        outputAction: mapping.output,
                        description: mapping.description
                    )

                    let displayName = cleanBundleId.split(separator: ".").last.map(String.init) ?? cleanBundleId

                    let keymap = AppKeymap(
                        bundleIdentifier: cleanBundleId,
                        displayName: displayName.capitalized,
                        overrides: [override]
                    )
                    result.appKeymaps.append(keymap)
                }
            }
        } else if !unlessConditions.isEmpty {
            // Only "unless" conditions — add as global mapping with warning
            let apps = unlessConditions.flatMap(\.bundleIdentifiers).joined(separator: ", ")
            result.warnings.append("'\(rule)' applies everywhere except [\(apps)] — imported as global rule (app exclusions not yet supported)")
            result.mappings.append(mapping)
        } else {
            result.mappings.append(mapping)
        }
    }

    // MARK: - Layer Variable Detection

    /// Detect variables used as on/off layer toggles.
    /// Pattern: set_variable name=X value=1 in `to`, set_variable name=X value=0 in `to_after_key_up`.
    private func detectLayerVariables(in manipulators: [KarabinerManipulator]) -> Set<String> {
        var layerVars = Set<String>()

        for manipulator in manipulators {
            if let toActions = manipulator.to {
                for to in toActions {
                    if let setVar = to.setVariable, setVar.value.isOn {
                        // Check if there's a corresponding off in to_after_key_up
                        if let afterKeyUp = manipulator.toAfterKeyUp {
                            for after in afterKeyUp {
                                if let afterVar = after.setVariable,
                                   afterVar.name == setVar.name,
                                   !afterVar.value.isOn
                                {
                                    layerVars.insert(setVar.name)
                                }
                            }
                        }
                    }
                }
            }
        }

        return layerVars
    }

    /// Check if a manipulator is purely a variable activator (layer toggle) with no key output.
    private func isVariableActivator(_ manipulator: KarabinerManipulator, layerVariables: Set<String>) -> Bool {
        guard let toActions = manipulator.to else { return false }

        let allAreVariables = toActions.allSatisfy { to in
            to.setVariable != nil && to.keyCode == nil && to.consumerKeyCode == nil && to.shellCommand == nil
        }

        if allAreVariables {
            return toActions.contains { to in
                if let name = to.setVariable?.name {
                    return layerVariables.contains(name)
                }
                return false
            }
        }

        return false
    }

    // MARK: - Launcher Persistence

    /// Persist launcher mappings into the existing launcher rule collection.
    /// Shared implementation used by both KarabinerImportSheet and WizardKarabinerImportPage.
    static func persistLauncherMappings(_ newMappings: [LauncherMapping]) async throws {
        var collections = await RuleCollectionStore.shared.loadCollections()
        guard let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) else { return }
        var collection = collections[index]
        guard var config = collection.configuration.launcherGridConfig else { return }

        config.mappings.append(contentsOf: newMappings)
        collection.configuration = .launcherGrid(config)
        collections[index] = collection
        try await RuleCollectionStore.shared.saveCollections(collections)
        NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
    }

    // MARK: - Deduplication

    private func deduplicateAppKeymaps(_ keymaps: [AppKeymap]) -> [AppKeymap] {
        var byBundleId: [String: Int] = [:] // bundleId → index in result
        var result: [AppKeymap] = []

        for keymap in keymaps {
            let bundleId = keymap.mapping.bundleIdentifier
            if let existingIndex = byBundleId[bundleId] {
                result[existingIndex].overrides.append(contentsOf: keymap.overrides)
            } else {
                byBundleId[bundleId] = result.count
                result.append(keymap)
            }
        }

        return result
    }
}
