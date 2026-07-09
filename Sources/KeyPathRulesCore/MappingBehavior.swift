import Foundation

// MARK: - Mapping Behavior

/// Describes advanced key behavior beyond a simple remap.
/// When present on a KeyMapping, the generator emits tap-hold, tap-dance, macro, or chord syntax.
public enum MappingBehavior: Codable, Equatable, Sendable {
    /// Dual-role key: tap produces one action, hold produces another.
    case dualRole(DualRoleBehavior)

    /// Tap behavior with optional multi-tap (tap-dance) behavior.
    case tapOrTapDance(TapOrTapDanceBehavior)

    /// Macro: one trigger key → multiple output keys or text string.
    case macro(MacroBehavior)

    /// Chord: multiple keys pressed together produce a single output.
    case chord(ChordBehavior)

    private enum CodingKeys: String, CodingKey {
        case dualRole
        case tapDance // legacy
        case tapOrTapDance
        case macro
        case chord
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let dualRole = try container.decodeIfPresent(DualRoleBehavior.self, forKey: .dualRole) {
            self = .dualRole(dualRole)
            return
        }

        if let tapOrTapDance = try container.decodeIfPresent(TapOrTapDanceBehavior.self, forKey: .tapOrTapDance) {
            self = .tapOrTapDance(tapOrTapDance)
            return
        }

        if let tapDance = try container.decodeIfPresent(TapDanceBehavior.self, forKey: .tapDance) {
            self = .tapOrTapDance(.tapDance(tapDance))
            return
        }

        if let macro = try container.decodeIfPresent(MacroBehavior.self, forKey: .macro) {
            self = .macro(macro)
            return
        }

        if let chord = try container.decodeIfPresent(ChordBehavior.self, forKey: .chord) {
            self = .chord(chord)
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .dualRole,
            in: container,
            debugDescription: "Unknown MappingBehavior case"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .dualRole(dualRole):
            try container.encode(dualRole, forKey: .dualRole)
        case let .tapOrTapDance(tapOrTapDance):
            try container.encode(tapOrTapDance, forKey: .tapOrTapDance)
        case let .macro(macro):
            try container.encode(macro, forKey: .macro)
        case let .chord(chord):
            try container.encode(chord, forKey: .chord)
        }
    }
}

// MARK: - Tap or Tap-Dance

/// Tap behavior with optional multi-tap (tap-dance) behavior.
public enum TapOrTapDanceBehavior: Codable, Equatable, Sendable {
    /// A single tap (no multi-tap configured).
    case tap

    /// Tap-dance: different actions for single tap, double tap, etc.
    case tapDance(TapDanceBehavior)
}

// MARK: - Dual Role

/// Settings for a tap-hold (dual-role) key.
///
/// **Variant Priority** (renderer uses first matching condition):
/// 1. `useReleaseOrder` → `tap-hold-release-order` (purely release-order based)
/// 2. `useOppositeHandRelease` → `tap-hold-opposite-hand-release` (release-time opposite-hand)
/// 3. `useOppositeHand` → `tap-hold-opposite-hand` (press-time opposite-hand HRM)
/// 4. `customTapKeys` (non-empty) → `tap-hold-release-keys` (legacy split-hand HRM)
/// 5. `activateHoldOnOtherKey` → `tap-hold-press`
/// 6. `quickTap` → `tap-hold-release`
/// 7. Otherwise → `tap-hold` (basic)
public struct DualRoleBehavior: Codable, Equatable, Sendable {
    /// Action when tapped (e.g., .keystroke(key: "a"), .keystroke(key: "esc")).
    public var tapAction: KeyAction

    /// Action when held (e.g., .keystroke(key: "lctl"), .hyper, or layer switch).
    public var holdAction: KeyAction

    /// Milliseconds before a press is considered a hold. Default 200. Must be > 0.
    public var tapTimeout: Int
    public var holdTimeout: Int
    public var activateHoldOnOtherKey: Bool
    public var quickTap: Bool
    public var customTapKeys: [String]
    public var useOppositeHand: Bool
    public var useOppositeHandRelease: Bool
    public var useReleaseOrder: Bool
    public var requirePriorIdleOverrideMs: Int?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tapAction = try container.decode(KeyAction.self, forKey: .tapAction)
        holdAction = try container.decode(KeyAction.self, forKey: .holdAction)
        tapTimeout = try container.decodeIfPresent(Int.self, forKey: .tapTimeout) ?? 200
        holdTimeout = try container.decodeIfPresent(Int.self, forKey: .holdTimeout) ?? 200
        activateHoldOnOtherKey = try container.decodeIfPresent(Bool.self, forKey: .activateHoldOnOtherKey) ?? false
        quickTap = try container.decodeIfPresent(Bool.self, forKey: .quickTap) ?? false
        customTapKeys = try container.decodeIfPresent([String].self, forKey: .customTapKeys) ?? []
        useOppositeHand = try container.decodeIfPresent(Bool.self, forKey: .useOppositeHand) ?? false
        useOppositeHandRelease = try container.decodeIfPresent(Bool.self, forKey: .useOppositeHandRelease) ?? false
        useReleaseOrder = try container.decodeIfPresent(Bool.self, forKey: .useReleaseOrder) ?? false
        requirePriorIdleOverrideMs = try container.decodeIfPresent(Int.self, forKey: .requirePriorIdleOverrideMs)
    }

    private enum CodingKeys: String, CodingKey {
        case tapAction, holdAction, tapTimeout, holdTimeout
        case activateHoldOnOtherKey, quickTap, customTapKeys
        case useOppositeHand, useOppositeHandRelease, useReleaseOrder
        case requirePriorIdleOverrideMs
    }

    public init(
        tapAction: KeyAction,
        holdAction: KeyAction,
        tapTimeout: Int = 200,
        holdTimeout: Int = 200,
        activateHoldOnOtherKey: Bool = false,
        quickTap: Bool = false,
        customTapKeys: [String] = [],
        useOppositeHand: Bool = false,
        useOppositeHandRelease: Bool = false,
        useReleaseOrder: Bool = false,
        requirePriorIdleOverrideMs: Int? = nil
    ) {
        self.tapAction = tapAction
        self.holdAction = holdAction
        self.tapTimeout = max(1, tapTimeout)
        self.holdTimeout = max(1, holdTimeout)
        self.activateHoldOnOtherKey = activateHoldOnOtherKey
        self.quickTap = quickTap
        self.customTapKeys = customTapKeys
        self.useOppositeHand = useOppositeHand
        self.useOppositeHandRelease = useOppositeHandRelease
        self.useReleaseOrder = useReleaseOrder
        self.requirePriorIdleOverrideMs = requirePriorIdleOverrideMs
    }

    public var isValid: Bool {
        !tapAction.isEmpty && !holdAction.isEmpty && tapTimeout > 0 && holdTimeout > 0
    }

    /// The tap action as a string (for UI display and backward compatibility).
    public var tapActionString: String {
        tapAction.outputString
    }

    /// The hold action as a string (for UI display and backward compatibility).
    public var holdActionString: String {
        holdAction.outputString
    }
}

// MARK: - Tap Dance

/// Settings for a tap-dance key.
public struct TapDanceBehavior: Codable, Equatable, Sendable {
    /// Time window (ms) to register additional taps. Default 200. Must be > 0.
    public var windowMs: Int

    /// Ordered list of actions for each tap count (index 0 = single tap, 1 = double, etc.).
    /// Must have at least one step with a non-empty action.
    public var steps: [TapDanceStep]

    public init(windowMs: Int = 200, steps: [TapDanceStep]) {
        self.windowMs = max(1, windowMs)
        self.steps = steps
    }

    public var isValid: Bool {
        windowMs > 0 && steps.contains { !$0.action.isEmpty }
    }

    /// Convenience init from string actions (for call sites migrating from string-based API).
    public static func twoStep(singleTap: KeyAction, doubleTap: KeyAction, windowMs: Int = 200) -> TapDanceBehavior {
        TapDanceBehavior(
            windowMs: windowMs,
            steps: [
                TapDanceStep(label: "Single tap", action: singleTap),
                TapDanceStep(label: "Double tap", action: doubleTap),
            ]
        )
    }
}

/// A single step in a tap-dance sequence.
public struct TapDanceStep: Codable, Equatable, Sendable {
    public var label: String

    /// The action to perform (keystroke, hyper, raw kanata, etc.).
    public var action: KeyAction

    public init(label: String, action: KeyAction) {
        self.label = label
        self.action = action
    }

    /// The action as a string (for UI display and backward compatibility).
    public var actionString: String {
        action.outputString
    }
}

// MARK: - Macro Behavior

/// A macro: one trigger key → multiple output keys or text string.
public struct MacroBehavior: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case text
        case keys
    }

    public var outputs: [String]
    public var text: String?
    public var description: String?
    public var source: Source

    public init(
        outputs: [String] = [],
        text: String? = nil,
        description: String? = nil,
        source: Source? = nil
    ) {
        self.outputs = outputs
        self.text = text
        self.description = description
        if let source {
            self.source = source
        } else {
            self.source = (text?.isEmpty == false) ? .text : .keys
        }
    }

    public var isValid: Bool {
        validationErrors.isEmpty
    }

    public var effectiveOutputs: [String] {
        switch source {
        case .text:
            if let text, !text.isEmpty {
                return text.map { String($0) }
            }
            return []
        case .keys:
            return outputs
        }
    }

    public var displayString: String {
        switch source {
        case .text:
            if let text, !text.isEmpty {
                return "\"\(text)\""
            }
            return "Not configured"
        case .keys:
            let keys = outputs.prefix(3).joined(separator: " ")
            return outputs.count > 3 ? "\(keys)..." : (keys.isEmpty ? "Not configured" : keys)
        }
    }

    public var validationErrors: [String] {
        var errors: [String] = []

        let outputs = effectiveOutputs
        if outputs.isEmpty {
            errors.append("Macro must include at least one output")
        }

        if source == .text, let text, !text.isEmpty {
            if let unsupported = TextToKanataKeyMapper.firstUnsupportedCharacter(in: text) {
                errors.append("Unsupported character: \(unsupported)")
            }
        }

        return errors
    }
}

// MARK: - Convenience Factories

public extension DualRoleBehavior {
    static func homeRowMod(letter: String, modifier: String) -> DualRoleBehavior {
        DualRoleBehavior(
            tapAction: .keystroke(key: letter),
            holdAction: .keystroke(key: modifier),
            tapTimeout: 200,
            holdTimeout: 200,
            activateHoldOnOtherKey: true,
            quickTap: false
        )
    }
}

public extension TapDanceBehavior {
    /// Create a simple two-step tap-dance from string actions (convenience).
    static func twoStepFromStrings(singleTap: String, doubleTap: String, windowMs: Int = 200) -> TapDanceBehavior {
        TapDanceBehavior(
            windowMs: windowMs,
            steps: [
                TapDanceStep(label: "Single tap", action: KeyAction.parseLegacyActionString(singleTap)),
                TapDanceStep(label: "Double tap", action: KeyAction.parseLegacyActionString(doubleTap)),
            ]
        )
    }
}

private extension KeyAction {
    static func parseLegacyActionString(_ action: String) -> KeyAction {
        let stripped = action.trimmingCharacters(in: .whitespacesAndNewlines)

        if stripped.hasPrefix("("), stripped.hasSuffix(")") {
            if let structured = parseStructuredLegacyAction(stripped) {
                return structured
            }
            return .rawKanata(stripped)
        }

        let lowercased = stripped.lowercased()
        if lowercased == "hyper" {
            return .hyper
        }
        if lowercased == "meh" {
            return .meh
        }

        let tokens = stripped
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if tokens.count > 1 {
            return .rawKanata("(multi \(tokens.joined(separator: " ")))")
        }

        return .keystroke(key: stripped)
    }

    static func parseStructuredLegacyAction(_ expr: String) -> KeyAction? {
        if let pushMsg = extractPushMsgValue(expr) {
            return parsePushMsg(pushMsg)
        }

        if expr == "(multi lctl lmet lalt lsft)" {
            return .hyper
        }
        if expr == "(multi lctl lalt lsft)" {
            return .meh
        }

        if let fakeKey = parseFakeKeyExpr(expr) {
            return fakeKey
        }

        if let layerName = parseLayerSwitchExpr(expr) {
            return .activateLayer(name: layerName)
        }

        return nil
    }

    static func extractPushMsgValue(_ expr: String) -> String? {
        let prefix = "(push-msg \""
        let suffix = "\")"
        guard expr.hasPrefix(prefix), expr.hasSuffix(suffix) else { return nil }
        let start = expr.index(expr.startIndex, offsetBy: prefix.count)
        let end = expr.index(expr.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        return String(expr[start ..< end])
    }

    static func parsePushMsg(_ value: String) -> KeyAction? {
        if let id = value.removingPrefix("launch:") {
            return .launchApp(name: id, bundleId: id)
        }
        if let encoded = value.removingPrefix("open:") {
            return .openURL(URLMappingFormatter.decodeFromPushMessage(encoded))
        }
        if let path = value.removingPrefix("folder:") {
            return .openFolder(path: path, name: nil)
        }
        if let path = value.removingPrefix("script:") {
            return .runScript(path: path, name: nil)
        }
        if let id = value.removingPrefix("system:") {
            return .systemAction(id: id)
        }
        if let params = value.removingPrefix("notify?") {
            return parseNotifyParams(params)
        }
        if let position = value.removingPrefix("window:") {
            return .windowAction(position: position)
        }
        return nil
    }

    static func parseNotifyParams(_ params: String) -> KeyAction? {
        var title = ""
        var body: String?
        var sound = false
        for part in params.components(separatedBy: "&") {
            if let val = part.removingPrefix("title=") {
                title = val
            } else if let val = part.removingPrefix("body=") {
                body = val
            } else if part == "sound=1" {
                sound = true
            }
        }
        guard !title.isEmpty else { return nil }
        return .notify(title: title, body: body, sound: sound)
    }

    static func parseFakeKeyExpr(_ expr: String) -> KeyAction? {
        let prefix = "(on-press-fakekey "
        guard expr.hasPrefix(prefix), expr.hasSuffix(")") else { return nil }
        let body = String(expr.dropFirst(prefix.count).dropLast())
        let parts = body.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let action = FakeKeyAction(rawValue: String(parts[1])) else { return nil }
        return .fakeKey(name: String(parts[0]), action: action)
    }

    static func parseLayerSwitchExpr(_ expr: String) -> String? {
        let prefix = "(layer-switch "
        guard expr.hasPrefix(prefix), expr.hasSuffix(")") else { return nil }
        let name = String(expr.dropFirst(prefix.count).dropLast())
        return name.isEmpty ? nil : name
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

// MARK: - Chord Behavior

/// Settings for a chord (multiple keys pressed together).
///
/// Chords allow combinations like j+k → Esc or s+d → Backspace.
/// Uses Kanata's `defchords` syntax for implementation.
public struct ChordBehavior: Codable, Equatable, Sendable {
    public var keys: [String]

    /// Action when chord is triggered (e.g., .keystroke(key: "esc"), .keystroke(key: "bspc")).
    public var output: KeyAction

    /// Time window (ms) for chord detection. Default 200. Must be > 0.
    /// Larger values make chords easier to trigger but may cause misfires.
    public var timeout: Int
    public var description: String?

    public init(
        keys: [String],
        output: KeyAction,
        timeout: Int = 200,
        description: String? = nil
    ) {
        self.keys = keys
        self.output = output
        self.timeout = max(50, timeout)
        self.description = description
    }

    public var isValid: Bool {
        keys.count >= 2 && !output.isEmpty && timeout >= 50
    }

    /// The output as a string (for UI display and backward compatibility).
    public var outputString: String {
        output.outputString
    }

    /// A unique group name for this chord (used in Kanata defchords).
    /// Generated from the sorted keys to ensure consistency.
    public var groupName: String {
        "kp-chord-" + keys.sorted().joined(separator: "-")
    }
}

// MARK: - Chord Convenience Factories

public extension ChordBehavior {
    /// Create a simple two-key chord.
    static func twoKey(_ key1: String, _ key2: String, output: KeyAction, description: String? = nil) -> ChordBehavior {
        ChordBehavior(keys: [key1, key2], output: output, description: description)
    }

    /// Create a three-key chord.
    static func threeKey(_ key1: String, _ key2: String, _ key3: String, output: KeyAction, description: String? = nil) -> ChordBehavior {
        ChordBehavior(keys: [key1, key2, key3], output: output, description: description)
    }
}
