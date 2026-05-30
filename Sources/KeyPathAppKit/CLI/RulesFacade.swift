import Foundation
import KeyPathCore

public struct RulesFacade: Sendable {
    public init() {}

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

        if existingIsSimple, newIsSimple {
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

        if case var .dualRole(existingDual) = existing.behavior, newIsSimple {
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

// MARK: - Rule Types

public struct CLICustomRule: Codable, Sendable {
    public let input: String
    public let output: String
    public let behavior: String?
}

public struct CLIRuleDetail: Codable, Sendable {
    public let input: String
    public let action: KeyAction
    public let behavior: MappingBehavior?
    public let shiftedOutput: String?
    public let title: String?
    public let notes: String?
    public let targetLayer: String
    public let deviceOverrides: [CLIDeviceOverride]?
    public let isEnabled: Bool
    public let createdAt: Date

    public init(from rule: CustomRule) {
        input = rule.input
        action = rule.action
        behavior = rule.behavior
        shiftedOutput = rule.shiftedOutput
        title = rule.title.isEmpty ? nil : rule.title
        notes = rule.notes
        targetLayer = rule.targetLayer.kanataName
        deviceOverrides = rule.deviceOverrides?.map { CLIDeviceOverride(from: $0) }
        isEnabled = rule.isEnabled
        createdAt = rule.createdAt
    }

    public static func dryRunPreview(
        input: String,
        action: KeyAction?,
        behavior: MappingBehavior?,
        shiftedOutput: String?,
        title: String?,
        notes: String?,
        targetLayer: String?
    ) -> CLIRuleDetail {
        CLIRuleDetail(
            input: input,
            action: action ?? .empty,
            behavior: behavior,
            shiftedOutput: shiftedOutput,
            title: title,
            notes: notes,
            targetLayer: targetLayer ?? "base",
            deviceOverrides: nil,
            isEnabled: true,
            createdAt: Date()
        )
    }

    public init(
        input: String,
        action: KeyAction,
        behavior: MappingBehavior?,
        shiftedOutput: String?,
        title: String?,
        notes: String?,
        targetLayer: String,
        deviceOverrides: [CLIDeviceOverride]?,
        isEnabled: Bool,
        createdAt: Date
    ) {
        self.input = input
        self.action = action
        self.behavior = behavior
        self.shiftedOutput = shiftedOutput
        self.title = title
        self.notes = notes
        self.targetLayer = targetLayer
        self.deviceOverrides = deviceOverrides
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

public struct CLIDeviceOverride: Codable, Sendable {
    public let deviceHash: String
    public let action: KeyAction
    public let behavior: MappingBehavior?

    public init(from override: DeviceKeyOverride) {
        deviceHash = override.deviceHash
        action = override.output
        behavior = override.behavior
    }
}

public enum RuleAddResult: Codable, Sendable {
    case created(CLIRuleDetail)
    case replaced(CLIRuleDetail)
    case merged(CLIRuleDetail)
    case skipped

    private enum CodingKeys: String, CodingKey {
        case status
        case rule
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        switch status {
        case "created":
            self = try .created(container.decode(CLIRuleDetail.self, forKey: .rule))
        case "replaced":
            self = try .replaced(container.decode(CLIRuleDetail.self, forKey: .rule))
        case "merged":
            self = try .merged(container.decode(CLIRuleDetail.self, forKey: .rule))
        case "skipped":
            self = .skipped
        default:
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "Unknown status: \(status)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .created(rule):
            try container.encode("created", forKey: .status)
            try container.encode(rule, forKey: .rule)
        case let .replaced(rule):
            try container.encode("replaced", forKey: .status)
            try container.encode(rule, forKey: .rule)
        case let .merged(rule):
            try container.encode("merged", forKey: .status)
            try container.encode(rule, forKey: .rule)
        case .skipped:
            try container.encode("skipped", forKey: .status)
        }
    }
}

public enum CLIConflictStrategy: String, Sendable {
    case fail
    case replace
    case skip
    case merge
}

public struct CLIMergeError: Error, CustomStringConvertible {
    public let input: String
    public let reason: String
    public var description: String {
        "Cannot merge rules for '\(input)': \(reason)"
    }
}

public struct CLIConflictError: Error, CustomStringConvertible {
    public let input: String
    public var description: String {
        "Rule already exists for '\(input)'"
    }
}
