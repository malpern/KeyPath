import KeyPathCore
import KeyPathRulesCore
import SwiftUI

extension RulesTabView {
    /// Get the current leader key value (from the Leader Key collection or default to Space)
    var currentLeaderKey: String {
        if let pendingToggle = pendingToggles[RuleCollectionIdentifier.leaderKey], !pendingToggle {
            return "space"
        }

        if let pending = pendingSelections[RuleCollectionIdentifier.leaderKey] {
            return pending
        }

        if let leaderCollection = allCollections.first(where: { $0.id == RuleCollectionIdentifier.leaderKey }) {
            let isEnabled = pendingToggles[RuleCollectionIdentifier.leaderKey] ?? leaderCollection.isEnabled
            if isEnabled, let selectedOutput = leaderCollection.configuration.singleKeyPickerConfig?.selectedOutput {
                return selectedOutput
            }
        }

        return "space"
    }

    /// Format leader key for display in activator hints
    var currentLeaderKeyDisplay: String {
        formatKeyWithSymbol(currentLeaderKey)
    }

    /// Generate a dynamic description for collections
    func dynamicCollectionDescription(for collection: RuleCollection) -> String {
        if case .launcherGrid = collection.configuration {
            return dynamicLauncherDescription(for: collection)
        }
        return collection.summary
    }

    /// Generate a dynamic activation hint for tap-hold picker collections
    func dynamicTapHoldActivationHint(for collection: RuleCollection) -> String? {
        guard case let .tapHoldPicker(config) = collection.configuration else {
            return nil
        }

        let tapOutput = config.selectedTapOutput ?? config.tapOptions.first?.output ?? "hyper"
        let holdOutput = config.selectedHoldOutput ?? config.holdOptions.first?.output ?? "hyper"
        let tapLabel = config.tapOptions.first { $0.output == tapOutput }?.label ?? tapOutput
        let holdLabel = config.holdOptions.first { $0.output == holdOutput }?.label ?? holdOutput

        return KeyboardConceptCopy.activationHint("Tap for \(tapLabel), or hold for \(holdLabel)")
    }

    /// Generate a dynamic description for launcher collections
    func dynamicLauncherDescription(for collection: RuleCollection) -> String {
        guard case let .launcherGrid(config) = collection.configuration else {
            return collection.summary
        }

        switch config.activationMode {
        case .holdHyper:
            return KeyboardConceptCopy.launcherActivationDescription(
                mode: config.activationMode,
                hyperTriggerMode: config.hyperTriggerMode
            )
        case .leaderSequence:
            return KeyboardConceptCopy.launcherActivationDescription(
                mode: config.activationMode,
                hyperTriggerMode: config.hyperTriggerMode,
                leaderKeyDisplay: currentLeaderKeyDisplay
            )
        }
    }

    /// Generate a dynamic activation hint for launcher collections
    func dynamicLauncherActivationHint(for collection: RuleCollection) -> String {
        guard case let .launcherGrid(config) = collection.configuration else {
            return collection.activationHint.map(KeyboardConceptCopy.activationHint)
                ?? KeyboardConceptCopy.activationHint("Hold Hyper, then press a shortcut key")
        }

        switch config.activationMode {
        case .holdHyper:
            switch config.hyperTriggerMode {
            case .hold:
                return KeyboardConceptCopy.activationHint("Hold Hyper, then press a shortcut key")
            case .tap:
                return KeyboardConceptCopy.activationHint("Tap Hyper to turn the launcher on or off, then press a shortcut key")
            }
        case .leaderSequence:
            return KeyboardConceptCopy.activationHint("Hold \(currentLeaderKeyDisplay), then press L, then a shortcut key")
        }
    }

    /// Get the activation hint for a collection
    func dynamicActivationHint(for collection: RuleCollection) -> String? {
        if case .launcherGrid = collection.configuration {
            return dynamicLauncherActivationHint(for: collection)
        }
        if case .tapHoldPicker = collection.configuration {
            return dynamicTapHoldActivationHint(for: collection)
        }
        if case .autoShiftSymbols = collection.configuration {
            return KeyboardConceptCopy.activationHint("Hold a supported key to type its shifted symbol")
        }
        if let wsMode = collection.windowSnappingActivationMode {
            switch wsMode {
            case .leader:
                return KeyboardConceptCopy.activationHint("Hold \(currentLeaderKeyDisplay), then press W, then an action key")
            case .quickLauncher:
                return KeyboardConceptCopy.activationHint("Hold Hyper, then press W, then an action key")
            }
        }
        return collection.activationHint.map(KeyboardConceptCopy.activationHint)
    }

    /// Returns tunable activation metadata without competing with the action-first hint.
    func dynamicActivationDetail(for collection: RuleCollection) -> String? {
        guard case let .autoShiftSymbols(config) = collection.configuration else {
            return nil
        }

        return "\(config.enabledKeys.count) supported keys · Hold delay \(config.timeoutMs) ms"
    }

    /// Generate a dynamic name for picker-style collections
    func dynamicCollectionName(for collection: RuleCollection) -> String {
        if collection.id == RuleCollectionIdentifier.homeRowMods,
           TypingFeelMapping.usesTopRow(collection.configuration.homeRowModsConfig?.enabledKeys ?? [])
        {
            return "Top Row Mods"
        }

        guard case let .singleKeyPicker(config) = collection.configuration else {
            return collection.name
        }

        let inputDisplay = formatKeyWithSymbol(config.inputKey)

        let effectiveEnabled: Bool = if let pendingToggle = pendingToggles[collection.id] {
            pendingToggle
        } else {
            collection.isEnabled
        }

        let selectedOutput = config.selectedOutput ?? config.presetOptions.first?.output ?? ""
        let outputLabel = config.presetOptions.first { $0.output == selectedOutput }?.label ?? selectedOutput

        guard effectiveEnabled else {
            if collection.momentaryActivator != nil {
                return "\(currentLeaderKeyDisplay) + \(inputDisplay) → \(outputLabel)"
            }
            return "\(inputDisplay) → \(outputLabel)"
        }

        let effectiveOutput: String = if let pending = pendingSelections[collection.id] {
            pending
        } else {
            selectedOutput
        }

        let effectiveOutputLabel = config.presetOptions.first { $0.output == effectiveOutput }?.label ?? effectiveOutput

        if collection.momentaryActivator != nil {
            return "\(currentLeaderKeyDisplay) + \(inputDisplay) → \(effectiveOutputLabel)"
        }

        return "\(inputDisplay) → \(effectiveOutputLabel)"
    }

    /// Format a modifier key for display
    func formatModifierForDisplay(_ modifier: String) -> String {
        let displayNames: [String: String] = [
            "lmet": "⌘", "rmet": "⌘",
            "lalt": "⌥", "ralt": "⌥",
            "lctl": "⌃", "rctl": "⌃",
            "lsft": "⇧", "rsft": "⇧",
        ]
        return displayNames[modifier] ?? modifier
    }

    /// Format a key name with its Mac symbol
    func formatKeyWithSymbol(_ key: String) -> String {
        let keySymbols: [String: String] = [
            "caps": "⇪ Caps Lock",
            "leader": "Leader",
            "lmet": "⌘ Command",
            "rmet": "⌘ Command",
            "lalt": "⌥ Option",
            "ralt": "⌥ Option",
            "lctl": "⌃ Control",
            "rctl": "⌃ Control",
            "lsft": "⇧ Shift",
            "rsft": "⇧ Shift",
            "esc": "⎋ Escape",
            "tab": "⇥ Tab",
            "ret": "↩ Return",
            "spc": "␣ Space",
            "space": "␣ Space",
            "bspc": "⌫ Delete",
            "del": "⌦ Forward Delete",
        ]
        return keySymbols[key.lowercased()] ?? key.capitalized
    }
}
