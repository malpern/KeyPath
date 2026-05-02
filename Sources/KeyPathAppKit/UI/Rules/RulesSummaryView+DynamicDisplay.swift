import KeyPathCore
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

        return "Tap: \(tapLabel), Hold: \(holdLabel)"
    }

    /// Generate a dynamic description for launcher collections
    func dynamicLauncherDescription(for collection: RuleCollection) -> String {
        guard case let .launcherGrid(config) = collection.configuration else {
            return collection.summary
        }

        switch config.activationMode {
        case .holdHyper:
            switch config.hyperTriggerMode {
            case .hold:
                return "Hold Hyper to quickly launch apps and websites with keyboard shortcuts."
            case .tap:
                return "Tap Hyper to toggle the launcher on/off. Then press a shortcut key."
            }
        case .leaderSequence:
            return "Press \(currentLeaderKeyDisplay) → L to activate the launcher layer."
        }
    }

    /// Generate a dynamic activation hint for launcher collections
    func dynamicLauncherActivationHint(for collection: RuleCollection) -> String {
        guard case let .launcherGrid(config) = collection.configuration else {
            return collection.activationHint ?? "Hold Hyper key"
        }

        switch config.activationMode {
        case .holdHyper:
            switch config.hyperTriggerMode {
            case .hold:
                return "Hold Hyper key"
            case .tap:
                return "Tap Hyper key"
            }
        case .leaderSequence:
            return "\(currentLeaderKeyDisplay) → L"
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
        if case let .autoShiftSymbols(config) = collection.configuration {
            return "\(config.enabledKeys.count) keys \u{00B7} \(config.timeoutMs)ms hold"
        }
        return collection.activationHint
    }

    /// Generate a dynamic name for picker-style collections
    func dynamicCollectionName(for collection: RuleCollection) -> String {
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
