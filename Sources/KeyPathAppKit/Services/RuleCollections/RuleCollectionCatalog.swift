import Foundation
import KeyPathCore
import KeyPathRulesCore

/// Provides predefined rule collections that ship with the app.
struct RuleCollectionCatalog {
    /// Why a built-in collection cannot run on the active backend, or nil. Derived
    /// from the keys the collection's catalog definition emits, so a collection
    /// becomes unavailable (or available) with the backend, not a hard-coded id.
    ///
    /// Uses the collection as a profile receives it (the fresh-profile default),
    /// not the raw catalog entry: macOS Function Keys is stored as its media
    /// definition but always installed in function mode, and media mode's own
    /// availability is `FunctionKeyMode.isSupportedInDriverlessSession`.
    ///
    /// The sentence is the admission engine's (phase 4d), so the gallery, the
    /// rules list and the toggle all say the same thing. Only the backend's
    /// own limits count here: whether a companion app is installed is a
    /// question for install or toggle time, with the user's real files.
    static func driverlessUnavailableReason(for id: UUID, profile: BackendCapabilityProfile = .shared) -> String? {
        guard let collection = installedDefinitions.first(where: { $0.id == id }) else { return nil }
        var enabled = collection
        enabled.isEnabled = true
        let state = AdmissionEngine.State(collections: [enabled])
        let verdicts = AdmissionEngine.evaluate(state, profile: profile, fileExists: { _ in true })
        guard let verdict = verdicts.first(where: { if case .unmetNeed = $0.reason { return true }; return false })
        else { return nil }
        return AdmissionVerdictPresenter.present(verdict) { _ in collection.name }.explanation
    }

    private static let installedDefinitions = RuleCollectionCatalog().defaultCollections()

    /// True when any key these mappings emit is outside the backend's profile.
    static func emitsUnsupportedOutput(_ mappings: [KeyMapping],
                                       profile: BackendCapabilityProfile = .shared) -> Bool
    {
        !RuleCollectionNeedsExtractor.unmet(RuleCollectionNeedsExtractor.needs(for: mappings), profile: profile).isEmpty
    }

    func defaultCollections() -> [RuleCollection] {
        // Fresh profiles use conservative keyboard behavior. Keep every built-in
        // definition available without silently changing persisted enable states.
        Self.builtInList.map { collection in
            var fresh = collection
            fresh.isEnabled = collection.id == RuleCollectionIdentifier.macFunctionKeys
            if fresh.id == RuleCollectionIdentifier.macFunctionKeys {
                fresh.functionKeyMode = .function
                fresh.mappings = Self.functionKeyMappings(for: .function)
            }
            return fresh
        }
    }

    /// The catalog's own definitions, before fresh-profile adjustments.
    func originalCollections() -> [RuleCollection] {
        Self.builtInList
    }

    /// Returns the launcher collection (managed separately via overlay drawer)
    func launcherCollection() -> RuleCollection {
        Self.builtInList.first { $0.id == RuleCollectionIdentifier.launcher }
            ?? RuleCollection(
                id: RuleCollectionIdentifier.launcher,
                name: "Quick Launcher",
                summary: KeyboardConceptCopy.launcherCatalogSummary,
                category: .layers,
                mappings: [],
                icon: "arrow.up.forward.app",
                configuration: .launcherGrid(LauncherGridConfig.defaultConfig)
            )
    }

    func upgradedCollection(from existing: RuleCollection) -> RuleCollection {
        guard let updated = builtInCollections[existing.id] else { return existing }
        var merged = updated
        merged.isEnabled = existing.isEnabled
        // Preserve user's configuration for configurable collections
        // (e.g., launcher mappings, home row mods settings, etc.)
        // Only if the configuration type matches - otherwise use catalog default
        if existing.configuration.displayStyle == updated.configuration.displayStyle {
            // For tapHoldPicker: preserve user's selections but use catalog's options
            // This ensures removed options (like "None") don't persist
            if case let .tapHoldPicker(existingConfig) = existing.configuration,
               case let .tapHoldPicker(catalogConfig) = updated.configuration
            {
                var mergedConfig = catalogConfig
                // Preserve user's selection only if it's still a valid option
                if let selectedTap = existingConfig.selectedTapOutput,
                   catalogConfig.tapOptions.contains(where: { $0.output == selectedTap })
                {
                    mergedConfig.selectedTapOutput = selectedTap
                }
                if let selectedHold = existingConfig.selectedHoldOutput,
                   catalogConfig.holdOptions.contains(where: { $0.output == selectedHold })
                {
                    mergedConfig.selectedHoldOutput = selectedHold
                }
                merged.configuration = .tapHoldPicker(mergedConfig)
            } else {
                merged.configuration = existing.configuration
            }
        }

        if existing.id == RuleCollectionIdentifier.windowSnapping {
            if let convention = existing.windowKeyConvention {
                merged.windowKeyConvention = convention
                merged.mappings = Self.preservingIdentity(of: existing.mappings,
                                                          in: Self.windowMappings(for: convention))
            }

            if let activationMode = existing.windowSnappingActivationMode {
                merged.windowSnappingActivationMode = activationMode
                merged.momentaryActivator = existing.momentaryActivator
                merged.activationHint = existing.activationHint
            }
        }

        if existing.id == RuleCollectionIdentifier.macFunctionKeys {
            merged.functionKeyMode = existing.functionKeyMode
            merged.mappings = existing.mappings
        }

        return merged
    }

    // MARK: - Catalog Data (loaded from JSON)

    private static let builtInList: [RuleCollection] = {
        guard let url = KeyPathAppKitResources.url(forResource: "rule-collection-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let collections = try? JSONDecoder().decode([RuleCollection].self, from: data)
        else {
            #if DEBUG
                print("RuleCollectionCatalog: Failed to load catalog from JSON")
            #endif
            return []
        }
        return collections
    }()

    private var builtInCollections: [UUID: RuleCollection] {
        Dictionary(uniqueKeysWithValues: Self.builtInList.map { ($0.id, $0) })
    }

    // MARK: - Dynamic Mapping Generators

    /// Generate window snapping key mappings for a given convention
    /// Regenerated mappings take the ids of the saved mappings they replace.
    /// Fresh ids made an unchanged collection compare unequal, so it was offered
    /// as a catalog update again after every apply.
    static func preservingIdentity(of existing: [KeyMapping], in regenerated: [KeyMapping]) -> [KeyMapping] {
        let ids = Dictionary(existing.map { ($0.input, $0.id) }, uniquingKeysWith: { first, _ in first })
        return regenerated.map { mapping in
            guard let id = ids[mapping.input] else { return mapping }
            return KeyMapping(
                id: id, input: mapping.input, action: mapping.action,
                shiftedOutput: mapping.shiftedOutput, ctrlOutput: mapping.ctrlOutput,
                description: mapping.description, sectionBreak: mapping.sectionBreak,
                sectionLabel: mapping.sectionLabel, behavior: mapping.behavior,
                deviceOverrides: mapping.deviceOverrides
            )
        }
    }

    static func windowMappings(for convention: WindowKeyConvention) -> [KeyMapping] {
        switch convention {
        case .standard:
            [
                KeyMapping(input: "l", action: .rawKanata(#"(push-msg "window:left")"#), description: "Left half"),
                KeyMapping(input: "r", action: .rawKanata(#"(push-msg "window:right")"#), description: "Right half"),
                KeyMapping(input: "m", action: .rawKanata(#"(push-msg "window:maximize")"#), description: "Maximize/Restore"),
                KeyMapping(input: "c", action: .rawKanata(#"(push-msg "window:center")"#), description: "Center"),
                KeyMapping(input: "u", action: .rawKanata(#"(push-msg "window:top-left")"#), description: "Top-left", sectionBreak: true),
                KeyMapping(input: "i", action: .rawKanata(#"(push-msg "window:top-right")"#), description: "Top-right"),
                KeyMapping(input: "j", action: .rawKanata(#"(push-msg "window:bottom-left")"#), description: "Bottom-left"),
                KeyMapping(input: "k", action: .rawKanata(#"(push-msg "window:bottom-right")"#), description: "Bottom-right"),
                KeyMapping(input: "[", action: .rawKanata(#"(push-msg "window:previous-display")"#), description: "Previous display", sectionBreak: true),
                KeyMapping(input: "]", action: .rawKanata(#"(push-msg "window:next-display")"#), description: "Next display"),
                KeyMapping(input: ",", action: .rawKanata(#"(push-msg "window:previous-space")"#), description: "Previous Space", sectionBreak: true),
                KeyMapping(input: ".", action: .rawKanata(#"(push-msg "window:next-space")"#), description: "Next Space"),
                KeyMapping(input: "z", action: .rawKanata(#"(push-msg "window:undo")"#), description: "Undo", sectionBreak: true)
            ]
        case .vim:
            [
                KeyMapping(input: "h", action: .rawKanata(#"(push-msg "window:left")"#), description: "Left half"),
                KeyMapping(input: "l", action: .rawKanata(#"(push-msg "window:right")"#), description: "Right half"),
                KeyMapping(input: "m", action: .rawKanata(#"(push-msg "window:maximize")"#), description: "Maximize/Restore"),
                KeyMapping(input: "c", action: .rawKanata(#"(push-msg "window:center")"#), description: "Center"),
                KeyMapping(input: "y", action: .rawKanata(#"(push-msg "window:top-left")"#), description: "Top-left", sectionBreak: true),
                KeyMapping(input: "u", action: .rawKanata(#"(push-msg "window:top-right")"#), description: "Top-right"),
                KeyMapping(input: "b", action: .rawKanata(#"(push-msg "window:bottom-left")"#), description: "Bottom-left"),
                KeyMapping(input: "n", action: .rawKanata(#"(push-msg "window:bottom-right")"#), description: "Bottom-right"),
                KeyMapping(input: "[", action: .rawKanata(#"(push-msg "window:previous-display")"#), description: "Previous display", sectionBreak: true),
                KeyMapping(input: "]", action: .rawKanata(#"(push-msg "window:next-display")"#), description: "Next display"),
                KeyMapping(input: "a", action: .rawKanata(#"(push-msg "window:previous-space")"#), description: "Previous Space", sectionBreak: true),
                KeyMapping(input: "s", action: .rawKanata(#"(push-msg "window:next-space")"#), description: "Next Space"),
                KeyMapping(input: "z", action: .rawKanata(#"(push-msg "window:undo")"#), description: "Undo", sectionBreak: true)
            ]
        }
    }

    /// Generate function key mappings for a given mode
    static func functionKeyMappings(for mode: FunctionKeyMode) -> [KeyMapping] {
        switch mode {
        case .media:
            [
                KeyMapping(input: "f1", action: .keystroke(key: "brdn"), description: "Brightness down"),
                KeyMapping(input: "f2", action: .keystroke(key: "brup"), description: "Brightness up"),
                KeyMapping(input: "f3", action: .rawKanata(#"(push-msg "system:mission-control")"#), description: "Mission Control"),
                KeyMapping(input: "f4", action: .rawKanata(#"(push-msg "system:spotlight")"#), description: "Spotlight"),
                KeyMapping(input: "f5", action: .rawKanata(#"(push-msg "system:dictation")"#), description: "Dictation"),
                KeyMapping(input: "f6", action: .rawKanata(#"(push-msg "system:dnd")"#), description: "Do Not Disturb"),
                KeyMapping(input: "f7", action: .keystroke(key: "prev"), description: "Previous track"),
                KeyMapping(input: "f8", action: .keystroke(key: "pp"), description: "Play / Pause"),
                KeyMapping(input: "f9", action: .keystroke(key: "next"), description: "Next track"),
                KeyMapping(input: "f10", action: .keystroke(key: "mute"), description: "Mute"),
                KeyMapping(input: "f11", action: .keystroke(key: "vold"), description: "Volume down"),
                KeyMapping(input: "f12", action: .keystroke(key: "volu"), description: "Volume up")
            ]
        case .function:
            [
                KeyMapping(input: "f1", action: .keystroke(key: "f1"), description: "F1"),
                KeyMapping(input: "f2", action: .keystroke(key: "f2"), description: "F2"),
                KeyMapping(input: "f3", action: .keystroke(key: "f3"), description: "F3"),
                KeyMapping(input: "f4", action: .keystroke(key: "f4"), description: "F4"),
                KeyMapping(input: "f5", action: .keystroke(key: "f5"), description: "F5"),
                KeyMapping(input: "f6", action: .keystroke(key: "f6"), description: "F6"),
                KeyMapping(input: "f7", action: .keystroke(key: "f7"), description: "F7"),
                KeyMapping(input: "f8", action: .keystroke(key: "f8"), description: "F8"),
                KeyMapping(input: "f9", action: .keystroke(key: "f9"), description: "F9"),
                KeyMapping(input: "f10", action: .keystroke(key: "f10"), description: "F10"),
                KeyMapping(input: "f11", action: .keystroke(key: "f11"), description: "F11"),
                KeyMapping(input: "f12", action: .keystroke(key: "f12"), description: "F12")
            ]
        }
    }
}

public extension FunctionKeyMode {
    /// Whether the active backend can emit every key this mode maps F1–F12 to.
    /// Media mode needs consumer-page output, which the driverless session lacks.
    var isSupportedInDriverlessSession: Bool {
        !RuleCollectionCatalog.emitsUnsupportedOutput(RuleCollectionCatalog.functionKeyMappings(for: self))
    }
}
