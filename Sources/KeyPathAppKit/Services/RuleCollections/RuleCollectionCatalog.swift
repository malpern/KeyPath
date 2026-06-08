import Foundation

/// Provides predefined rule collections that ship with the app.
struct RuleCollectionCatalog {
    func defaultCollections() -> [RuleCollection] {
        Self.builtInList
    }

    /// Returns the launcher collection (managed separately via overlay drawer)
    func launcherCollection() -> RuleCollection {
        Self.builtInList.first { $0.id == RuleCollectionIdentifier.launcher }
            ?? RuleCollection(
                id: RuleCollectionIdentifier.launcher,
                name: "Quick Launcher",
                summary: "Hold Hyper to quickly launch apps and websites with keyboard shortcuts.",
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
                merged.mappings = Self.windowMappings(for: convention)
            }

            if let activationMode = existing.windowSnappingActivationMode {
                merged.windowSnappingActivationMode = activationMode
                merged.momentaryActivator = existing.momentaryActivator
                merged.activationHint = existing.activationHint
            }
        }

        if existing.id == RuleCollectionIdentifier.macFunctionKeys,
           let mode = existing.functionKeyMode
        {
            merged.functionKeyMode = mode
            merged.mappings = Self.functionKeyMappings(for: mode)
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
