import Foundation
import KeyPathCore
import KeyPathDaemonLifecycle
import KeyPathRulesCore
import Network

/// Point-in-time non-rule inputs for synchronous configuration rendering.
/// Capture these in the owning service before rendering; the renderer itself
/// must not mix a candidate with live disk, cache, or preference state.
struct KanataGenerationInputs {
    let leaderKeyPreference: LeaderKeyPreference?
    let navActivationMode: ContextHUDTriggerMode
    let navHoldDelayMs: Int
    let deviceGenerationInput: DeviceGenerationInput
    let chordGroups: [ChordGroupConfig]
    let sequences: [KanataDefseqParser.ParsedSequence]
    let appSpecificKeys: Set<String>
    let physicalLayout: PhysicalLayout

    init(
        leaderKeyPreference: LeaderKeyPreference? = nil,
        navActivationMode: ContextHUDTriggerMode = .tapToToggle,
        navHoldDelayMs: Int = 200,
        deviceGenerationInput: DeviceGenerationInput = DeviceGenerationInput(selections: [], connectedDevices: []),
        chordGroups: [ChordGroupConfig] = [],
        sequences: [KanataDefseqParser.ParsedSequence] = [],
        appSpecificKeys: Set<String> = [],
        physicalLayout: PhysicalLayout = .macBookUS
    ) {
        self.leaderKeyPreference = leaderKeyPreference
        self.navActivationMode = navActivationMode
        self.navHoldDelayMs = navHoldDelayMs
        self.deviceGenerationInput = deviceGenerationInput
        self.chordGroups = chordGroups
        self.sequences = sequences
        self.appSpecificKeys = appSpecificKeys
        self.physicalLayout = physicalLayout
    }

    static let empty = KanataGenerationInputs()
}

// MARK: - Kanata Configuration Model

/// Represents Kanata configuration data and metadata
public struct KanataConfiguration: Sendable {
    public let content: String
    public let keyMappings: [KeyMapping]
    public let lastModified: Date
    public let path: String
    public let chordGroups: [ChordGroupConfig]
    public let sequences: [KanataDefseqParser.ParsedSequence]

    public init(
        content: String,
        keyMappings: [KeyMapping],
        lastModified: Date,
        path: String,
        chordGroups: [ChordGroupConfig] = [],
        sequences: [KanataDefseqParser.ParsedSequence] = []
    ) {
        self.content = content
        self.keyMappings = keyMappings
        self.lastModified = lastModified
        self.path = path
        self.chordGroups = chordGroups
        self.sequences = sequences
    }

    /// Generate configuration content from key mappings (adds default system collections when absent).
    public static func generateFromMappings(_ mappings: [KeyMapping]) -> String {
        let collections = [RuleCollection].collection(named: "Custom Mappings", mappings: mappings)
        return generateFromCollections(collections, inputs: .empty)
    }

    /// Generate configuration content from rule collections.
    /// Flattens enabled collections to `defsrc`/`deflayer` for backward compatibility with Kanata config format.
    static func generateFromCollections(
        _ collections: [RuleCollection],
        inputs: KanataGenerationInputs
    ) -> String {
        var resolvedCollections = collections.isEmpty ? defaultSystemCollections : collections
        if !resolvedCollections.contains(where: { $0.id == RuleCollectionIdentifier.macFunctionKeys }) {
            resolvedCollections.append(contentsOf: defaultSystemCollections)
        }
        resolvedCollections = RuleCollectionDeduplicator.dedupe(resolvedCollections)
        let enabledCollections = resolvedCollections.filter(\.isEnabled)
        // Note: Disabled collections are NOT written to config (ADR-025: JSON stores are source of truth)

        // Extract UI-authored chord groups config (MAL-37)
        let uiChordGroupsConfig = enabledCollections
            .compactMap(\.configuration.chordGroupsConfig)
            .first

        AppLogger.shared.log("📚 [KanataConfig] Enabled collections: \(enabledCollections.map { "\($0.name) (enabled: \($0.isEnabled))" }.joined(separator: ", "))")

        // Extract max tap-hold-require-prior-idle value from the collections that intentionally
        // use a shared defcfg-level setting. When active, ALL un-overridden tap-hold actions
        // require the specified idle gap. Auto Shift is deliberately excluded: it renders a
        // per-action override so its fast-typing protection cannot affect other collections.
        // Leader/nav keys get per-action (require-prior-idle 0) overrides so they still
        // activate immediately during fast typing.
        // Computed before buildCollectionBlocks so leader key can use per-action override when active.
        let requirePriorIdleMs = enabledCollections.compactMap { collection -> Int? in
            switch collection.configuration {
            case let .homeRowMods(config):
                config.timing.requirePriorIdleMs
            case let .homeRowLayerToggles(config):
                config.timing.requirePriorIdleMs
            default:
                nil
            }
        }.max() ?? 0

        let (rawBlocks, aliasDefinitions, extraLayers, chordMappings) = buildCollectionBlocks(
            from: enabledCollections,
            leaderKeyPreference: inputs.leaderKeyPreference,
            navActivationMode: inputs.navActivationMode,
            navHoldDelayMs: inputs.navHoldDelayMs,
            connectedDevices: inputs.deviceGenerationInput.connectedDevices,
            physicalLayout: inputs.physicalLayout,
            globalRequirePriorIdleMs: requirePriorIdleMs
        )
        let mergedAliasDefinitions = deduplicateAliases(aliasDefinitions)
        AppLogger.shared
            .log(
                "📚 [KanataConfig] Total alias definitions: \(mergedAliasDefinitions.count) (before dedup: \(aliasDefinitions.count)), first 5: \(mergedAliasDefinitions.prefix(5).map(\.aliasName).joined(separator: ", "))"
            )
        let blocks = deduplicateBlocks(rawBlocks)
        let enabledNames = enabledCollections.map(\.name).joined(separator: ", ")

        let macosDeviceTargeting = renderMacOSDeviceTargetingForDefcfg(inputs.deviceGenerationInput)
        let keyRepeatConfig = enabledCollections
            .compactMap(\.configuration.keyRepeatControlConfig)
            .first
        let sequencesConfig = enabledCollections
            .compactMap(\.configuration.sequencesConfig)
            .first
        let hasSequences = !inputs.sequences.isEmpty || !(sequencesConfig?.sequences.isEmpty ?? true)
        let sequencePauseLimitMs = hasSequences ? sequencesConfig?.clampedPauseLimitMs : nil

        // All defcfg header construction flows through KanataDefcfg (single source of truth).
        // `concurrent-tap-hold` is required by kanata whenever defchordsv2 is emitted, which
        // happens iff an enabled collection has chord inputs (→ non-empty chordMappings).
        let repeatTiming: (delayMs: Int, intervalMs: Int)? = {
            guard let krc = keyRepeatConfig, krc.isEnabled else { return nil }
            return (krc.globalDelayMs, krc.globalIntervalMs)
        }()
        let defcfg = KanataDefcfg.standard(
            managedRepeatTiming: repeatTiming,
            requirePriorIdleMs: requirePriorIdleMs > 0 ? requirePriorIdleMs : nil,
            sequenceTimeoutMs: sequencePauseLimitMs,
            hasChords: !chordMappings.isEmpty,
            deviceTargeting: macosDeviceTargeting
        )
        let header = ";; Generated by KeyPath\n"
            + ";; Enabled: \(enabledNames.isEmpty ? "none" : enabledNames)\n\n"
            + defcfg.render()

        let safetyNotes = """
        ;; SAFETY: This configuration is auto-generated. Do not edit by hand.
        ;; SAFETY: Only explicitly enabled mappings are written to this file.
        ;; EMERGENCY EXIT: Hold Left Control + Space + Escape to force-quit Kanata
        """

        let defvarBlock = renderDefvarBlock()

        // Emit defhands block if any enabled collection uses opposite-hand activation
        let needsDefhands = enabledCollections.contains { collection in
            switch collection.configuration {
            case let .homeRowMods(config):
                config.oppositeHandActivation
            case let .homeRowLayerToggles(config):
                config.oppositeHandActivation
            default:
                false
            }
        }
        let handAssignment: HandAssignment? = needsDefhands ? .qwertyDefault : nil
        let defhandsBlock = renderDefhandsBlock(handAssignment)

        let sourceBlock = renderDefsrcBlock(blocks)

        let appSpecificKeys = inputs.appSpecificKeys

        let baseLayerBlock = renderLayerBlock(name: RuleCollectionLayer.base.kanataName, blocks: blocks) { entry in
            // If this key has app-specific overrides, use the alias instead of the plain key
            // This enables the switch expression in keypath-apps.kbd to intercept the key
            let keyName = entry.sourceKey.lowercased()
            if appSpecificKeys.contains(keyName) {
                return appSpecificAliasName(for: keyName)
            }
            return entry.baseOutput
        }
        let additionalLayerBlocks = extraLayers.map { layer in
            renderLayerBlock(name: layer.kanataName, blocks: blocks) { entry in
                entry.layerOutputs[layer] ?? "_"
            }
        }.joined(separator: "\n")
        let fakeKeysBlock = renderFakeKeysBlock(extraLayers)
        let aliasBlock = renderAliasBlock(mergedAliasDefinitions)
        let chordsBlock = renderChordsBlock(chordMappings)
        let preservedChordGroupsBlock = renderChordGroupsBlock(inputs.chordGroups)
        let preservedSequencesBlock = renderSequencesBlock(inputs.sequences)
        let uiChordGroupsBlock = renderUIChordGroupsBlock(uiChordGroupsConfig)

        // Include keypath-apps.kbd if there are app-specific keys
        // This must come after defcfg but before any layer that uses @kp-* aliases
        let appIncludeBlock = if !appSpecificKeys.isEmpty {
            """
            ;; App-specific keymaps (virtual keys and switch expressions)
            (include keypath-apps.kbd)
            """
        } else {
            ""
        }

        let defrepeatBlock: String = {
            guard let krc = keyRepeatConfig, krc.isEnabled, !krc.perKeyOverrides.isEmpty else {
                return ""
            }
            let entries = krc.perKeyOverrides
                .map { "  (\($0.key)  \($0.delayMs) \($0.intervalMs))" }
                .joined(separator: "\n")
            return "(defrepeat\n\(entries)\n)"
        }()

        return [
            header,
            safetyNotes,
            appIncludeBlock,
            defvarBlock,
            defrepeatBlock,
            defhandsBlock,
            sourceBlock,
            aliasBlock, // Must come before layers that reference aliases (e.g., @kp-ac-spc)
            baseLayerBlock,
            additionalLayerBlocks,
            fakeKeysBlock,
            chordsBlock,
            preservedSequencesBlock,
            preservedChordGroupsBlock,
            uiChordGroupsBlock
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    /// Compatibility convenience for callers that do not own all point-in-time inputs yet.
    /// It deliberately supplies deterministic empty values instead of consulting live state.
    static func generateFromCollections(
        _ collections: [RuleCollection],
        leaderKeyPreference: LeaderKeyPreference? = nil,
        navActivationMode: ContextHUDTriggerMode = .tapToToggle,
        navHoldDelayMs: Int = 200,
        deviceGenerationInput: DeviceGenerationInput? = nil,
        chordGroups: [ChordGroupConfig] = [],
        sequences: [KanataDefseqParser.ParsedSequence] = [],
        appSpecificKeys: Set<String> = []
    ) -> String {
        generateFromCollections(
            collections,
            inputs: KanataGenerationInputs(
                leaderKeyPreference: leaderKeyPreference,
                navActivationMode: navActivationMode,
                navHoldDelayMs: navHoldDelayMs,
                deviceGenerationInput: deviceGenerationInput ?? DeviceGenerationInput(selections: [], connectedDevices: []),
                chordGroups: chordGroups,
                sequences: sequences,
                appSpecificKeys: appSpecificKeys
            )
        )
    }

    private static let defaultEmptyConfig = generateFromCollections(defaultSystemCollections, inputs: .empty)

    // MARK: - macOS Device Targeting (VirtualHID exclusion + per-device selection)

    /// On macOS, Kanata may try to intercept *all* keyboards, including the VirtualHID output keyboard.
    /// If it grabs the VirtualHID device, it can create feedback loops (especially with symmetric remaps like 1<->2).
    ///
    /// Additionally, users may selectively disable remapping for specific keyboards via the Devices tab.
    /// When all non-VirtualHID devices are enabled (the default), we emit only `macos-dev-names-exclude`.
    /// When any non-VirtualHID device is disabled, we emit `macos-dev-names-include` for enabled devices
    /// plus `macos-dev-names-exclude` for VirtualHID devices.
    private static func renderMacOSDeviceTargetingForDefcfg(
        _ input: DeviceGenerationInput
    ) -> String {
        #if os(macOS)
            let allDevices = input.connectedDevices
            guard !allDevices.isEmpty else { return "" }

            let virtualHIDDevices = allDevices.filter(\.isVirtualHID)
            let physicalDevices = allDevices.filter { !$0.isVirtualHID }

            // Check which physical devices are disabled via user selection
            let enabledByHash = Dictionary(
                input.selections.map { ($0.hash, $0.isEnabled) },
                uniquingKeysWith: { _, latest in latest }
            )
            let isEnabled: (String) -> Bool = { enabledByHash[$0] ?? true }
            let disabledPhysical = physicalDevices.filter { !isEnabled($0.hash) }
            let enabledPhysical = physicalDevices.filter { isEnabled($0.hash) }

            // VirtualHID exclusion (always needed)
            let virtualHIDNames = virtualHIDDevices.flatMap { [$0.hash, $0.productKey] }.sorted()

            if disabledPhysical.isEmpty {
                // Default behavior: all physical keyboards remapped, only exclude VirtualHID
                guard !virtualHIDNames.isEmpty else { return "" }
                let rendered = virtualHIDNames.map { "    \"\($0)\"" }.joined(separator: "\n")
                AppLogger.shared.log("🧩 [KanataConfig] Excluding macOS devices from interception: \(virtualHIDNames.joined(separator: ", "))")
                return """

                  ;; Avoid grabbing VirtualHID output keyboard(s); prevents feedback loops.
                  macos-dev-names-exclude (
                \(rendered)
                  )
                """
            } else {
                // Selective mode: include only enabled physical devices, exclude VirtualHID
                let includeNames = enabledPhysical.map(\.hash).sorted()
                let excludeNames = virtualHIDNames

                AppLogger.shared.log("🧩 [KanataConfig] Device targeting: include \(includeNames.count) device(s), exclude \(excludeNames.count) VirtualHID name(s)")

                var result = ""
                if !includeNames.isEmpty {
                    let renderedInclude = includeNames.map { "    \"\($0)\"" }.joined(separator: "\n")
                    result += """

                      ;; Only remap selected keyboards (user device selection).
                      macos-dev-names-include (
                    \(renderedInclude)
                      )
                    """
                } else {
                    // All physical devices disabled — emit include with impossible name
                    // so Kanata grabs nothing. The UI warns the user about this state.
                    result += """

                      ;; All keyboards disabled by user — remap nothing.
                      macos-dev-names-include (
                        "__keypath_no_devices__"
                      )
                    """
                }
                if !excludeNames.isEmpty {
                    let renderedExclude = excludeNames.map { "    \"\($0)\"" }.joined(separator: "\n")
                    result += """

                      ;; Avoid grabbing VirtualHID output keyboard(s); prevents feedback loops.
                      macos-dev-names-exclude (
                    \(renderedExclude)
                      )
                    """
                }
                return result
            }
        #else
            return ""
        #endif
    }

    #if os(macOS)
        /// Parse the output of `kanata --list` and return device identifiers suitable for
        /// `macos-dev-names-exclude`. Kept as a pure function for unit testing.
        /// Used by legacy callers — new code should use `DeviceEnumerationService.parseAllDevices`.
        static func parseExcludedMacOSDeviceNames(fromKanataList output: String) -> [String] {
            let devices = DeviceEnumerationService.parseAllDevices(fromKanataList: output)
            var results = Set<String>()
            for device in devices where device.isVirtualHID {
                results.insert(device.hash)
                results.insert(device.productKey)
            }
            return results.sorted()
        }
    #endif
}
