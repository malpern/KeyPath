import Foundation
import KeyPathCore

enum LayerMappingBuilder {
    // MARK: - Pipeline Steps

    static func augmentWithPushMsgActions(
        mapping: [UInt16: LayerKeyInfo],
        customRules: [CustomRule],
        ruleCollections: [RuleCollection],
        currentLayerName: String
    ) -> [UInt16: LayerKeyInfo] {
        var augmented = mapping
        var actionByInput: [String: LayerKeyInfo] = [:]

        for collection in ruleCollections where collection.isEnabled {
            let collectionLayerName = collection.targetLayer.kanataName.lowercased()
            let currentLayer = currentLayerName.lowercased()

            guard collectionLayerName == currentLayer else {
                AppLogger.shared.debug("🗺️ [LayerMappingBuilder] Skipping collection '\(collection.name)' (targets '\(collectionLayerName)', current layer '\(currentLayer)')")
                continue
            }

            for keyMapping in collection.mappings {
                let input = keyMapping.input.lowercased()
                if let info = extractPushMsgInfo(from: keyMapping.action.kanataOutput, description: keyMapping.description) {
                    actionByInput[input] = info
                } else {
                    let outputKey = keyMapping.action.outputString.lowercased()
                    if let description = keyMapping.description,
                       let outputKeyCode = KanataKeyCodeMap.keyCode(for: outputKey)
                    {
                        actionByInput[input] = .mapped(
                            displayLabel: description,
                            outputKey: outputKey,
                            outputKeyCode: outputKeyCode,
                            collectionId: collection.id
                        )
                    } else if let systemAction = SystemActionInfo.find(byOutput: outputKey) {
                        actionByInput[input] = .systemAction(
                            action: systemAction.id,
                            description: keyMapping.description ?? systemAction.name,
                            collectionId: collection.id
                        )
                    } else if let outputKeyCode = KanataKeyCodeMap.keyCode(for: outputKey) {
                        let displayLabel = outputKey.count == 1 ? outputKey.uppercased() : outputKey.capitalized
                        actionByInput[input] = .mapped(
                            displayLabel: displayLabel,
                            outputKey: outputKey,
                            outputKeyCode: outputKeyCode,
                            collectionId: collection.id
                        )
                    }
                }
            }

            if case let .homeRowMods(config) = collection.configuration,
               config.holdMode == .modifiers
            {
                for key in config.enabledKeys {
                    guard let modifier = config.modifierAssignments[key],
                          let displayLabel = KeyDisplayFormatter.tapHoldLabel(for: modifier)
                    else { continue }
                    let input = KanataKeyConverter.convertToKanataKey(key).lowercased()
                    let info = LayerKeyInfo.mapped(
                        displayLabel: displayLabel,
                        outputKey: modifier,
                        outputKeyCode: nil,
                        collectionId: collection.id
                    )
                    actionByInput[input] = info
                    // Overlay key names are not always the same canonical strings used in
                    // saved HRM config (for example ";" vs "semicolon"). Register both
                    // forms so physical keycode lookup still resolves the modifier label.
                    if let keyCode = KanataKeyCodeMap.keyCode(for: key) {
                        let overlayInput = KanataKeyCodeMap.overlayName(for: keyCode).lowercased()
                        actionByInput[overlayInput] = info
                    }
                }
            } else if case let .homeRowMods(config) = collection.configuration,
                      config.holdMode == .layers
            {
                for key in config.enabledKeys {
                    guard let layerName = config.layerAssignments[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !layerName.isEmpty
                    else { continue }
                    let input = KanataKeyConverter.convertToKanataKey(key).lowercased()
                    let info = LayerKeyInfo.mapped(
                        displayLabel: LayerInfo.displayName(for: layerName),
                        outputKey: layerName,
                        outputKeyCode: nil,
                        collectionId: collection.id
                    )
                    actionByInput[input] = info
                    // Overlay key names are not always the same canonical strings used in
                    // saved HRM config (for example ";" vs "semicolon"). Register both
                    // forms so physical keycode lookup still resolves the layer label.
                    if let keyCode = KanataKeyCodeMap.keyCode(for: key) {
                        let overlayInput = KanataKeyCodeMap.overlayName(for: keyCode).lowercased()
                        actionByInput[overlayInput] = info
                    }
                }
            }
        }

        for rule in customRules where rule.isEnabled {
            let ruleLayerName = rule.targetLayer.kanataName.lowercased()
            let currentLayer = currentLayerName.lowercased()

            guard ruleLayerName == currentLayer else {
                continue
            }

            let input = rule.input.lowercased()
            if let info = extractPushMsgInfo(from: rule.action.kanataOutput, description: rule.notes) {
                actionByInput[input] = info
            } else {
                let outputKey = rule.action.outputString.lowercased()

                if let systemAction = SystemActionInfo.find(byOutput: outputKey) {
                    actionByInput[input] = .systemAction(
                        action: systemAction.id,
                        description: systemAction.name
                    )
                } else if let outputKeyCode = KanataKeyCodeMap.keyCode(for: outputKey) {
                    let displayLabel = outputKey.count == 1 ? outputKey.uppercased() : outputKey.capitalized
                    actionByInput[input] = .mapped(
                        displayLabel: displayLabel,
                        outputKey: outputKey,
                        outputKeyCode: outputKeyCode
                    )
                }
            }
        }

        AppLogger.shared.info("🗺️ [LayerMappingBuilder] Found \(actionByInput.count) actions (push-msg + simple remaps)")

        for (keyCode, originalInfo) in mapping {
            let keyName = KanataKeyCodeMap.overlayName(for: keyCode).lowercased()
            if let info = actionByInput[keyName] {
                let resolvedInfo = mergeAugmentation(info, with: originalInfo)
                augmented[keyCode] = resolvedInfo
            }
        }

        return augmented
    }

    static func enrichWithCustomShiftLabels(
        mapping: [UInt16: LayerKeyInfo],
        customRules: [CustomRule]
    ) -> [UInt16: LayerKeyInfo] {
        var shiftOverrides: [String: String] = [:]
        for rule in customRules where rule.isEnabled {
            guard let shiftedOutput = rule.shiftedOutput, !shiftedOutput.isEmpty else { continue }
            shiftOverrides[rule.input.lowercased()] = KeyDisplayFormatter.format(shiftedOutput)
        }
        guard !shiftOverrides.isEmpty else { return mapping }

        var result = mapping
        for (keyCode, info) in mapping {
            let kanataName = KanataKeyCodeMap.overlayName(for: keyCode)
            if let customShift = shiftOverrides[kanataName.lowercased()] {
                result[keyCode] = LayerKeyInfo(
                    displayLabel: info.displayLabel,
                    outputKey: info.outputKey,
                    outputKeyCode: info.outputKeyCode,
                    isTransparent: info.isTransparent,
                    isLayerSwitch: info.isLayerSwitch,
                    appLaunchIdentifier: info.appLaunchIdentifier,
                    systemActionIdentifier: info.systemActionIdentifier,
                    urlIdentifier: info.urlIdentifier,
                    collectionId: info.collectionId,
                    vimLabel: info.vimLabel,
                    customShiftLabel: customShift
                )
            }
        }
        return result
    }

    static func buildRemapOutputMap(from mapping: [UInt16: LayerKeyInfo]) -> [UInt16: UInt16] {
        var result: [UInt16: UInt16] = [:]
        for (inputKeyCode, info) in mapping {
            guard let outputKeyCode = info.outputKeyCode,
                  outputKeyCode != inputKeyCode,
                  !info.isTransparent
            else {
                continue
            }
            result[inputKeyCode] = outputKeyCode
        }
        return result
    }

    // MARK: - Merge

    static func mergeAugmentation(
        _ augmented: LayerKeyInfo,
        with original: LayerKeyInfo
    ) -> LayerKeyInfo {
        let collectionId = original.collectionId ?? augmented.collectionId
        let vimLabel = original.vimLabel ?? augmented.vimLabel
        let displayLabel = vimLabel != nil
            ? (original.displayLabel.isEmpty ? augmented.displayLabel : original.displayLabel)
            : augmented.displayLabel

        return LayerKeyInfo(
            displayLabel: displayLabel,
            outputKey: augmented.outputKey ?? original.outputKey,
            outputKeyCode: augmented.outputKeyCode ?? original.outputKeyCode,
            isTransparent: augmented.isTransparent,
            isLayerSwitch: augmented.isLayerSwitch,
            appLaunchIdentifier: augmented.appLaunchIdentifier,
            systemActionIdentifier: augmented.systemActionIdentifier,
            urlIdentifier: augmented.urlIdentifier,
            collectionId: collectionId,
            vimLabel: vimLabel
        )
    }

    // MARK: - Push-Msg Parsing

    private static let pushMsgTypeValueRegex = try? NSRegularExpression(
        pattern: #"\(push-msg\s+\"([^:\"]+):([^\"]+)\"\)"#,
        options: [.caseInsensitive]
    )

    private static let pushMsgLaunchRegex = try? NSRegularExpression(
        pattern: #"\(push-msg\s+\"launch:([^\"]+)\"\)"#,
        options: [.caseInsensitive]
    )

    private static let pushMsgOpenRegex = try? NSRegularExpression(
        pattern: #"\(push-msg\s+\"open:([^\"]+)\"\)"#,
        options: [.caseInsensitive]
    )

    private static let pushMsgSystemRegex = try? NSRegularExpression(
        pattern: #"\(push-msg\s+\"system:([^\"]+)\"\)"#,
        options: [.caseInsensitive]
    )

    static func extractPushMsgInfo(from output: String, description: String?) -> LayerKeyInfo? {
        guard let pushMsgTypeValueRegex,
              let match = pushMsgTypeValueRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let typeRange = Range(match.range(at: 1), in: output),
              let valueRange = Range(match.range(at: 2), in: output)
        else {
            return nil
        }

        let msgType = String(output[typeRange]).lowercased()
        let msgValue = String(output[valueRange])

        switch msgType {
        case "launch":
            return .appLaunch(appIdentifier: msgValue)
        case "system":
            let displayLabel = description ?? systemActionDisplayLabel(msgValue)
            return .systemAction(action: msgValue, description: displayLabel)
        case "open":
            return .webURL(url: URLMappingFormatter.decodeFromPushMessage(msgValue))
        default:
            return .pushMsg(message: description ?? msgValue)
        }
    }

    static func extractAppLaunchIdentifier(from output: String) -> String? {
        guard let pushMsgLaunchRegex,
              let match = pushMsgLaunchRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        let value = String(output[range])
        return URLMappingFormatter.decodeFromPushMessage(value)
    }

    static func extractUrlIdentifier(from output: String) -> String? {
        guard let pushMsgOpenRegex,
              let match = pushMsgOpenRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        let value = String(output[range])
        return URLMappingFormatter.decodeFromPushMessage(value)
    }

    static func extractSystemActionIdentifier(from output: String) -> String? {
        guard let pushMsgSystemRegex,
              let match = pushMsgSystemRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        return String(output[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func systemActionDisplayLabel(_ action: String) -> String {
        switch action.lowercased() {
        case "dnd", "do-not-disturb", "donotdisturb", "focus":
            "Do Not Disturb"
        case "spotlight":
            "Spotlight"
        case "dictation":
            "Dictation"
        case "mission-control", "missioncontrol":
            "Mission Control"
        case "launchpad":
            "Launchpad"
        case "notification-center", "notificationcenter":
            "Notification Center"
        case "siri":
            "Siri"
        default:
            action.capitalized
        }
    }

    static func mediaKeyDisplayLabel(_ kanataKey: String) -> String? {
        switch kanataKey.lowercased() {
        case "brup": "Brightness Up"
        case "brdn", "brdown": "Brightness Down"
        case "volu": "Volume Up"
        case "vold", "voldwn": "Volume Down"
        case "mute": "Mute"
        case "pp": "Play/Pause"
        case "next": "Next Track"
        case "prev": "Previous Track"
        default: nil
        }
    }
}
