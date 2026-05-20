import Foundation
import KeyPathCore

// MARK: - Custom Rules

extension CLIFacade {
    public func loadCustomRules() async -> [CLICustomRule] {
        let rules = await CustomRulesStore.shared.loadRules()
        return rules.map { CLICustomRule(input: $0.input, output: $0.action.outputString, behavior: $0.behavior.map(Self.describeBehavior)) }
    }

    static func describeBehavior(_ behavior: MappingBehavior) -> String {
        switch behavior {
        case let .dualRole(d):
            "tap-hold: tap=\(d.tapActionString), hold=\(d.holdActionString), timeout=\(d.tapTimeout)ms"
        case .tapOrTapDance(.tap):
            "tap"
        case let .tapOrTapDance(.tapDance(td)):
            "tap-dance: \(td.steps.map(\.actionString).joined(separator: ", "))"
        case let .macro(m):
            "macro: \(m.text ?? m.outputs.joined(separator: " "))"
        case let .chord(c):
            "chord: \(c.keys.joined(separator: "+")) → \(c.outputString)"
        }
    }

    @discardableResult
    public func addSimpleRemap(input: String, output: String) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let hadExisting = rules.contains { $0.input == input }
        rules.removeAll { $0.input == input }
        let rule = CustomRule(input: input, action: .keystroke(key: output))
        rules.append(rule)
        try await CustomRulesStore.shared.saveRules(rules)
        return hadExisting
    }

    @discardableResult
    public func addTapHoldRemap(input: String, tap: String, hold: String, timeout: Int = 200) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let hadExisting = rules.contains { $0.input == input }
        rules.removeAll { $0.input == input }
        let rule = CustomRule(
            input: input,
            action: .keystroke(key: tap),
            behavior: .dualRole(DualRoleBehavior(
                tapAction: .keystroke(key: tap),
                holdAction: .keystroke(key: hold),
                tapTimeout: timeout
            ))
        )
        rules.append(rule)
        try await CustomRulesStore.shared.saveRules(rules)
        return hadExisting
    }

    public func addRule(
        input: String,
        action: KeyAction,
        behavior: MappingBehavior? = nil,
        shiftedOutput: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        targetLayer: String? = nil,
        deviceOverrides: [DeviceKeyOverride]? = nil,
        onConflict: CLIConflictStrategy = .fail
    ) async throws -> RuleAddResult {
        var rules = await CustomRulesStore.shared.loadRules()
        let existingIndex = rules.firstIndex(where: { $0.input == input })

        if let existingIndex {
            switch onConflict {
            case .fail:
                throw CLIConflictError(input: input)
            case .skip:
                return .skipped
            case .replace:
                rules.removeAll { $0.input == input }
            case .merge:
                let existing = rules[existingIndex]
                let merged = try Self.mergeRules(existing: existing, newAction: action, newBehavior: behavior)
                rules[existingIndex] = merged
                try await CustomRulesStore.shared.saveRules(rules)
                return .merged(CLIRuleDetail(from: merged))
            }
        }

        let layer: RuleCollectionLayer = if let targetLayer {
            Self.parseLayer(targetLayer)
        } else {
            .base
        }

        let rule = CustomRule(
            title: title ?? "",
            input: input,
            action: action,
            shiftedOutput: shiftedOutput,
            notes: notes,
            behavior: behavior,
            targetLayer: layer,
            deviceOverrides: deviceOverrides
        )
        rules.append(rule)
        try await CustomRulesStore.shared.saveRules(rules)

        let detail = CLIRuleDetail(from: rule)
        return existingIndex != nil ? .replaced(detail) : .created(detail)
    }

    public func listRules(enabledOnly: Bool = false) async -> [CLIRuleDetail] {
        let rules = await CustomRulesStore.shared.loadRules()
        let filtered = enabledOnly ? rules.filter(\.isEnabled) : rules
        return filtered.map { CLIRuleDetail(from: $0) }
    }

    public func showRule(input: String) async -> CLIRuleDetail? {
        let rules = await CustomRulesStore.shared.loadRules()
        guard let rule = rules.first(where: { $0.input == input }) else { return nil }
        return CLIRuleDetail(from: rule)
    }

    public func removeRemap(input: String) async throws -> Bool {
        var rules = await CustomRulesStore.shared.loadRules()
        let before = rules.count
        rules.removeAll { $0.input == input }
        if rules.count == before { return false }
        try await CustomRulesStore.shared.saveRules(rules)
        return true
    }

    public func enableRule(input: String) async throws -> String? {
        var rules = await CustomRulesStore.shared.loadRules()
        guard let index = rules.firstIndex(where: { $0.input.caseInsensitiveCompare(input) == .orderedSame }) else {
            return nil
        }
        rules[index].isEnabled = true
        try await CustomRulesStore.shared.saveRules(rules)
        return rules[index].displayTitle
    }

    public func disableRule(input: String) async throws -> String? {
        var rules = await CustomRulesStore.shared.loadRules()
        guard let index = rules.firstIndex(where: { $0.input.caseInsensitiveCompare(input) == .orderedSame }) else {
            return nil
        }
        rules[index].isEnabled = false
        try await CustomRulesStore.shared.saveRules(rules)
        return rules[index].displayTitle
    }

    static func parseLayer(_ name: String) -> RuleCollectionLayer {
        switch name.lowercased() {
        case "base": .base
        case "nav", "navigation": .navigation
        default: .custom(name)
        }
    }

    static func mergeRules(existing: CustomRule, newAction: KeyAction, newBehavior: MappingBehavior?) throws -> CustomRule {
        let existingIsSimple = existing.behavior == nil
        let newIsSimple = newBehavior == nil

        if existingIsSimple && newIsSimple {
            throw CLIMergeError(
                input: existing.input,
                reason: "both rules are simple remaps with different outputs — ambiguous"
            )
        }

        var merged = existing

        if existingIsSimple, case let .dualRole(newDual) = newBehavior {
            merged.behavior = .dualRole(DualRoleBehavior(
                tapAction: existing.action,
                holdAction: newDual.holdAction,
                tapTimeout: newDual.tapTimeout,
                holdTimeout: newDual.holdTimeout,
                activateHoldOnOtherKey: newDual.activateHoldOnOtherKey
            ))
            merged.action = existing.action
            return merged
        }

        if case .dualRole(var existingDual) = existing.behavior, newIsSimple {
            existingDual.tapAction = newAction
            merged.behavior = .dualRole(existingDual)
            merged.action = newAction
            return merged
        }

        if case let .dualRole(existingDual) = existing.behavior,
           case let .dualRole(newDual) = newBehavior
        {
            merged.behavior = .dualRole(DualRoleBehavior(
                tapAction: newDual.tapAction,
                holdAction: newDual.holdAction,
                tapTimeout: newDual.tapTimeout,
                holdTimeout: existingDual.holdTimeout,
                activateHoldOnOtherKey: newDual.activateHoldOnOtherKey
            ))
            merged.action = newDual.tapAction
            return merged
        }

        throw CLIMergeError(
            input: existing.input,
            reason: "incompatible behavior types cannot be merged"
        )
    }
}
