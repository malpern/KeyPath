import Foundation

// MARK: - Hyper Linked Layer Info

/// Information about a layer that should be activated when Hyper is triggered
public struct HyperLinkedLayerInfo: Equatable, Sendable {
    public let layerName: String
    public let triggerMode: HyperTriggerMode

    public init(layerName: String, triggerMode: HyperTriggerMode = .hold) {
        self.layerName = layerName
        self.triggerMode = triggerMode
    }
}

// MARK: - Kanata Behavior Renderer

/// Renders `MappingBehavior` values to Kanata configuration syntax.
public enum KanataBehaviorRenderer {
    /// Render a mapping's behavior (or simple output) to Kanata syntax.
    /// - Parameters:
    ///   - mapping: The key mapping to render.
    ///   - hyperLinkedLayers: Layers that should be activated when "hyper" is triggered (legacy).
    /// - Returns: Kanata action string (e.g., `(tap-hold 200 200 a lctl)` or just `esc`).
    public static func render(_ mapping: KeyMapping, hyperLinkedLayers: [String] = []) -> String {
        // Convert legacy format to new format (default to hold mode)
        let layerInfos = hyperLinkedLayers.map { HyperLinkedLayerInfo(layerName: $0) }
        return render(mapping, hyperLinkedLayerInfos: layerInfos)
    }

    /// Render a mapping's behavior (or simple output) to Kanata syntax.
    /// - Parameters:
    ///   - mapping: The key mapping to render.
    ///   - hyperLinkedLayerInfos: Layers with trigger mode info for "hyper" activation.
    /// - Returns: Kanata action string (e.g., `(tap-hold 200 200 a lctl)` or just `esc`).
    public static func render(_ mapping: KeyMapping, hyperLinkedLayerInfos: [HyperLinkedLayerInfo]) -> String {
        guard let behavior = mapping.behavior else {
            // No advanced behavior—fall back to simple output rendering
            return KanataKeyConverter.convertToKanataSequence(mapping.action.kanataOutput)
        }

        switch behavior {
        case let .dualRole(dr):
            return renderDualRole(dr, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        case let .tapOrTapDance(tapOrTap):
            return renderTapOrTapDance(tapOrTap, mapping: mapping, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        case let .macro(macro):
            return renderMacro(macro)
        case let .chord(ch):
            return renderChord(ch, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        }
    }

    // MARK: - Chord

    /// Render a chord behavior.
    /// Note: Chords in Kanata require special handling - they need a defchords block.
    /// For individual mappings, we return an alias reference that must be defined
    /// in a defchords section elsewhere in the config.
    private static func renderChord(_ ch: ChordBehavior, hyperLinkedLayerInfos _: [HyperLinkedLayerInfo]) -> String {
        // For chord behavior, we return an alias that references the chord
        // The actual defchords definition must be generated separately
        // Format: @chord-{groupName}
        // This allows the chord to be referenced in deflayer while the
        // defchords block is generated at config level
        "@\(ch.groupName)"
    }

    /// Generate a defchords block for a chord behavior.
    /// This should be called by the config generator to create the chord definition.
    /// Format: (defchords groupname timeout (key1 key2 ...) output)
    public static func renderChordDefinition(_ ch: ChordBehavior, hyperLinkedLayerInfos: [HyperLinkedLayerInfo] = []) -> String {
        let keys = ch.keys.map { KanataKeyConverter.convertToKanataKey($0) }.joined(separator: " ")
        let output = convertAction(ch.output, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        return "(defchords \(ch.groupName) \(ch.timeout)\n  (\(keys)) \(output)\n)"
    }

    // MARK: - Dual Role

    /// Render a dual-role (tap-hold) behavior.
    /// Chooses the appropriate Kanata variant based on flags.
    private static func renderDualRole(_ dr: DualRoleBehavior, hyperLinkedLayerInfos: [HyperLinkedLayerInfo]) -> String {
        // Split linked layers by trigger mode so tap/hold behave as configured.
        let tapLinkedLayers = hyperLinkedLayerInfos.filter { $0.triggerMode == .tap }

        // Tap-mode layers should be available even when hyper is produced by a hold action
        // (e.g., Caps Lock tap=Esc, hold=Hyper). Pass all linked layers to holdAction.
        let tapAction = convertAction(dr.tapAction, hyperLinkedLayerInfos: tapLinkedLayers)
        let holdAction = convertAction(dr.holdAction, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        let tapTimeout = dr.tapTimeout
        let holdTimeout = dr.holdTimeout

        // Use variables for timeouts if they match defaults, otherwise use literal values
        // This allows users to customize timing via defvar while preserving custom values
        let tapTimeoutStr = tapTimeout == 200 ? "$tap-timeout" : "\(tapTimeout)"
        let holdTimeoutStr = holdTimeout == 200 ? "$hold-timeout" : "\(holdTimeout)"

        // Choose variant based on flags (priority: releaseOrder > oppositeHandRelease > oppositeHand > customTapKeys > activateHoldOnOtherKey > quickTap > basic)
        let base: String
        if dr.useReleaseOrder {
            // tap-hold-release-order: purely release-order based, no timeout latency.
            // Kanata PR #1970: (tap-hold-release-order <buffer-ms> <tap> <hold>)
            base = "(tap-hold-release-order \(tapTimeoutStr) \(tapAction) \(holdAction))"
        } else if dr.useOppositeHandRelease {
            // tap-hold-opposite-hand-release: release-time opposite-hand detection.
            // More forgiving than press-time — waits for interrupting key's press+release.
            // Kanata PR #1991: (tap-hold-opposite-hand-release <timeout> <tap> <hold>)
            base = "(tap-hold-opposite-hand-release \(holdTimeoutStr) \(tapAction) \(holdAction))"
        } else if dr.useOppositeHand {
            // tap-hold-opposite-hand: press-time opposite-hand detection via defhands.
            // Uses a single timeout (hold-time) — not dual tap/hold timeouts.
            // Kanata PR #1955: (tap-hold-opposite-hand <timeout> <tap> <hold>)
            base = "(tap-hold-opposite-hand \(holdTimeoutStr) \(tapAction) \(holdAction))"
        } else if !dr.customTapKeys.isEmpty {
            // tap-hold-release-keys: early tap on specific keys (legacy split-hand HRM)
            let keys = dr.customTapKeys.map { KanataKeyConverter.convertToKanataKey($0) }.joined(separator: " ")
            base = "(tap-hold-release-keys \(tapTimeoutStr) \(holdTimeoutStr) \(tapAction) \(holdAction) (\(keys)))"
        } else if dr.activateHoldOnOtherKey {
            // tap-hold-press: hold triggers on any other key press
            base = "(tap-hold-press \(tapTimeoutStr) \(holdTimeoutStr) \(tapAction) \(holdAction))"
        } else if dr.quickTap {
            // tap-hold-release: hold triggers on release of another key
            base = "(tap-hold-release \(tapTimeoutStr) \(holdTimeoutStr) \(tapAction) \(holdAction))"
        } else {
            // Basic tap-hold: pure timeout-based
            base = "(tap-hold \(tapTimeoutStr) \(holdTimeoutStr) \(tapAction) \(holdAction))"
        }

        // Per-action require-prior-idle override: appends trailing option to any tap-hold variant.
        // When nil, the global defcfg tap-hold-require-prior-idle value applies.
        if let overrideMs = dr.requirePriorIdleOverrideMs {
            // Insert trailing option before the closing paren
            let trimmed = base.dropLast() // remove trailing ")"
            return "\(trimmed) (require-prior-idle \(overrideMs)))"
        }
        return base
    }

    // MARK: - Tap Dance

    /// Render a tap-dance behavior.
    /// Format: `(tap-dance timeout (action1 action2 ...))`
    private static func renderTapDance(_ td: TapDanceBehavior, hyperLinkedLayerInfos: [HyperLinkedLayerInfo]) -> String {
        guard !td.steps.isEmpty else {
            // Edge case: empty steps—return passthrough
            return "_"
        }

        let actions = td.steps.map { step in
            convertAction(step.action, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        }

        // Kanata tap-dance syntax: (tap-dance timeout (action1 action2 ...))
        return "(tap-dance \(td.windowMs) (\(actions.joined(separator: " "))))"
    }

    // MARK: - Tap or Tap-Dance

    private static func renderTapOrTapDance(
        _ behavior: TapOrTapDanceBehavior,
        mapping: KeyMapping,
        hyperLinkedLayerInfos: [HyperLinkedLayerInfo]
    ) -> String {
        switch behavior {
        case .tap:
            KanataKeyConverter.convertToKanataSequence(mapping.action.kanataOutput)
        case let .tapDance(tapDance):
            renderTapDance(tapDance, hyperLinkedLayerInfos: hyperLinkedLayerInfos)
        }
    }

    // MARK: - Macro

    private static func renderMacro(_ macro: MacroBehavior) -> String {
        let outputs = macro.effectiveOutputs
        guard !outputs.isEmpty else { return "_" }

        if macro.source == .text, let text = macro.text, !text.isEmpty {
            switch TextToKanataKeyMapper.map(text: text) {
            case let .success(keys):
                return "(macro \(keys.joined(separator: " ")))"
            case .failure:
                return "_"
            }
        }

        let keys = outputs.map { KanataKeyConverter.convertToKanataKeyForMacro($0) }
        return "(macro \(keys.joined(separator: " ")))"
    }

    // MARK: - Action Conversion

    /// Convert a KeyAction to Kanata syntax, handling hyper with linked layers.
    static func convertAction(_ action: KeyAction, hyperLinkedLayerInfos: [HyperLinkedLayerInfo]) -> String {
        if case .hyper = action, !hyperLinkedLayerInfos.isEmpty {
            return renderHyperWithLayers(hyperLinkedLayerInfos)
        }
        return action.kanataOutput
    }

    /// Parse a string action into a typed KeyAction.
    /// Used by convertAction as the single parsing entry point.
    static func parseActionString(_ action: String) -> KeyAction {
        let stripped = action.trimmingCharacters(in: .whitespacesAndNewlines)

        // S-expressions: try structured parsing before falling back to rawKanata
        if stripped.hasPrefix("("), stripped.hasSuffix(")") {
            if let structured = parseStructuredAction(stripped) {
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

        // Check for space-separated tokens (multi-key action)
        let tokens = stripped
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        if tokens.count > 1 {
            let kanataKeys = tokens.map { KanataKeyConverter.convertToKanataKey($0) }
            return .rawKanata("(multi \(kanataKeys.joined(separator: " ")))")
        }

        // Single key — normalize through KanataKeyConverter
        let converted = KanataKeyConverter.convertToKanataKey(stripped)
        return .keystroke(key: converted)
    }

    /// Attempt to parse a Kanata S-expression into a structured KeyAction case.
    /// Returns nil if the expression doesn't match any known structured pattern.
    private static func parseStructuredAction(_ expr: String) -> KeyAction? {
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

    /// Extract the quoted value from `(push-msg "VALUE")`.
    private static func extractPushMsgValue(_ expr: String) -> String? {
        let prefix = "(push-msg \""
        let suffix = "\")"
        guard expr.hasPrefix(prefix), expr.hasSuffix(suffix) else { return nil }
        let start = expr.index(expr.startIndex, offsetBy: prefix.count)
        let end = expr.index(expr.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        return String(expr[start ..< end])
    }

    /// Parse a push-msg payload into the appropriate KeyAction.
    private static func parsePushMsg(_ value: String) -> KeyAction? {
        if let id = value.stripPrefix("launch:") {
            return .launchApp(name: id, bundleId: id)
        }
        if let encoded = value.stripPrefix("open:") {
            return .openURL(URLMappingFormatter.decodeFromPushMessage(encoded))
        }
        if let path = value.stripPrefix("folder:") {
            return .openFolder(path: path, name: nil)
        }
        if let path = value.stripPrefix("script:") {
            return .runScript(path: path, name: nil)
        }
        if let id = value.stripPrefix("system:") {
            return .systemAction(id: id)
        }
        if let params = value.stripPrefix("notify?") {
            return parseNotifyParams(params)
        }
        if let position = value.stripPrefix("window:") {
            return .windowAction(position: position)
        }
        return nil
    }

    /// Parse `title=X&body=Y&sound=1` into a `.notify` action.
    private static func parseNotifyParams(_ params: String) -> KeyAction? {
        var title = ""
        var body: String?
        var sound = false
        for part in params.components(separatedBy: "&") {
            if let val = part.stripPrefix("title=") {
                title = val
            } else if let val = part.stripPrefix("body=") {
                body = val
            } else if part == "sound=1" {
                sound = true
            }
        }
        guard !title.isEmpty else { return nil }
        return .notify(title: title, body: body, sound: sound)
    }

    /// Parse `(on-press-fakekey NAME ACTION)` into a `.fakeKey` action.
    private static func parseFakeKeyExpr(_ expr: String) -> KeyAction? {
        let prefix = "(on-press-fakekey "
        guard expr.hasPrefix(prefix), expr.hasSuffix(")") else { return nil }
        let body = String(expr.dropFirst(prefix.count).dropLast())
        let parts = body.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let action = FakeKeyAction(rawValue: String(parts[1])) else { return nil }
        return .fakeKey(name: String(parts[0]), action: action)
    }

    /// Parse `(layer-switch NAME)` into an `.activateLayer` action.
    private static func parseLayerSwitchExpr(_ expr: String) -> String? {
        let prefix = "(layer-switch "
        guard expr.hasPrefix(prefix), expr.hasSuffix(")") else { return nil }
        let name = String(expr.dropFirst(prefix.count).dropLast())
        return name.isEmpty ? nil : name
    }

    /// Render hyper with linked layer activations (context-dependent output).
    private static func renderHyperWithLayers(_ hyperLinkedLayerInfos: [HyperLinkedLayerInfo]) -> String {
        var components = ["lctl", "lmet", "lalt", "lsft"]
        for layerInfo in hyperLinkedLayerInfos {
            let layerName = layerInfo.layerName
            switch layerInfo.triggerMode {
            case .hold:
                components.append("(layer-while-held \(layerName))")
                components.append("(on-press-fakekey kp-layer-\(layerName)-enter tap)")
                components.append("(on-release-fakekey kp-layer-\(layerName)-exit tap)")
            case .tap:
                components.append("(on-press-fakekey kp-layer-\(layerName)-enter tap)")
                components.append("(one-shot-pause-processing 10)")
                components.append("(one-shot-press 5000 (layer-while-held \(layerName)))")
            }
        }
        return "(multi \(components.joined(separator: " ")))"
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
