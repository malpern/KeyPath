import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import Network

extension KanataConfiguration {
    /// Generate KeyMapping instances from HomeRowModsConfig
    static func generateHomeRowModsMappings(from config: HomeRowModsConfig) -> [KeyMapping] {
        var mappings: [KeyMapping] = []

        for key in config.enabledKeys {
            guard let modifier = config.modifierAssignments[key] else { continue }

            let tapTimeout = max(
                1,
                config.timing.tapWindow
                    + (config.timing.tapOffsets[key] ?? 0)
                    + (config.timing.quickTapEnabled ? config.timing.quickTapTermMs : 0)
            )
            let holdTimeout = max(1, config.timing.holdDelay + (config.timing.holdOffsets[key] ?? 0))

            // Create dual-role behavior: tap = letter, hold = modifier
            let behavior = DualRoleBehavior(
                tapAction: key,
                holdAction: modifier,
                tapTimeout: tapTimeout,
                holdTimeout: holdTimeout,
                activateHoldOnOtherKey: true, // Best for home-row mods
                quickTap: config.timing.quickTapEnabled,
                customTapKeys: []
            )

            let mapping = KeyMapping(
                input: key,
                output: key, // Fallback, but behavior takes precedence
                behavior: .dualRole(behavior)
            )
            mappings.append(mapping)
        }

        return mappings
    }

    /// Generate KeyMapping instances from HomeRowLayerTogglesConfig
    static func generateHomeRowLayerTogglesMappings(from config: HomeRowLayerTogglesConfig) -> [KeyMapping] {
        var mappings: [KeyMapping] = []

        for key in config.enabledKeys {
            guard let layerName = config.layerAssignments[key] else { continue }

            let tapTimeout = max(
                1,
                config.timing.tapWindow
                    + (config.timing.tapOffsets[key] ?? 0)
                    + (config.timing.quickTapEnabled ? config.timing.quickTapTermMs : 0)
            )
            let holdTimeout = max(1, config.timing.holdDelay + (config.timing.holdOffsets[key] ?? 0))

            // Build hold action based on toggle mode
            let holdAction = "(\(config.toggleMode.kanataAction) \(layerName))"

            // Create dual-role behavior: tap = letter, hold = layer activation
            let behavior = DualRoleBehavior(
                tapAction: key,
                holdAction: holdAction,
                tapTimeout: tapTimeout,
                holdTimeout: holdTimeout,
                activateHoldOnOtherKey: true, // Activate layer on other key press
                quickTap: config.timing.quickTapEnabled,
                customTapKeys: []
            )

            let mapping = KeyMapping(
                input: key,
                output: key, // Fallback, but behavior takes precedence
                behavior: .dualRole(behavior)
            )
            mappings.append(mapping)
        }

        return mappings
    }

    /// Generate KeyMapping instances from ChordGroupsConfig
    /// Each participating key maps to: (chord groupName key)
    static func generateChordGroupsMappings(from config: ChordGroupsConfig) -> [KeyMapping] {
        var mappings: [KeyMapping] = []

        // Process all groups
        for group in config.groups {
            // Get all keys that participate in this group
            let participatingKeys = group.participatingKeys

            // For each participating key, create a mapping: input → (chord groupName key)
            for key in participatingKeys {
                let output = "(chord \(group.name) \(key))"
                let mapping = KeyMapping(
                    input: key,
                    output: output
                    // behavior: nil (default) = simple remap
                )
                mappings.append(mapping)
            }
        }

        return mappings
    }

    /// Generate mappings for a tap-hold picker collection (e.g., Caps Lock Remap)
    static func generateTapHoldPickerMappings(from collection: RuleCollection) -> [KeyMapping] {
        guard case let .tapHoldPicker(config) = collection.configuration else {
            return []
        }

        let tapOutput = config.selectedTapOutput ?? config.tapOptions.first?.output ?? "hyper"
        let holdOutput = config.selectedHoldOutput ?? config.holdOptions.first?.output ?? "hyper"

        // Create dual-role behavior: tap = tapOutput, hold = holdOutput
        let behavior = DualRoleBehavior(
            tapAction: tapOutput,
            holdAction: holdOutput,
            tapTimeout: 200,
            holdTimeout: 200,
            activateHoldOnOtherKey: true,
            quickTap: false,
            customTapKeys: []
        )

        let mapping = KeyMapping(
            input: config.inputKey,
            output: tapOutput, // Fallback, but behavior takes precedence
            behavior: .dualRole(behavior)
        )

        return [mapping]
    }

    /// Generate mappings for a layer preset picker collection (e.g., Symbol Layer)
    static func generateLayerPresetMappings(from collection: RuleCollection) -> [KeyMapping] {
        guard case let .layerPresetPicker(config) = collection.configuration else {
            return collection.mappings
        }

        guard !config.presets.isEmpty else {
            return collection.mappings
        }

        return config.selectedMappings.isEmpty ? (config.presets.first?.mappings ?? []) : config.selectedMappings
    }

    /// Generate key mappings from launcher grid configuration
    static func generateLauncherGridMappings(from config: LauncherGridConfig) -> [KeyMapping] {
        let isTapMode = config.hyperTriggerMode == .tap

        var mappings = config.mappings
            .filter(\.isEnabled)
            // In tap mode, ESC is reserved for canceling the one-shot, so filter it out
            .filter { !isTapMode || $0.key.lowercased() != "esc" }
            .map { mapping in
                let output = if isTapMode {
                    "(multi \(mapping.target.kanataOutput) (push-msg \"layer:base\"))"
                } else {
                    mapping.target.kanataOutput
                }
                return KeyMapping(
                    input: mapping.key,
                    output: output
                )
            }

        // In tap mode, add ESC → XX (no output) to cancel one-shot without side effects
        if isTapMode {
            mappings.append(KeyMapping(input: "esc", output: "(multi XX (push-msg \"layer:base\"))"))
        }

        return mappings
    }
}
