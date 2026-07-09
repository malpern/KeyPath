import Foundation
import KeyPathCore

extension MapperViewModel {
    var canSave: Bool {
        inputSequence != nil && (outputSequence != nil || selectedApp != nil || selectedSystemAction != nil || selectedURL != nil)
    }

    var hasShiftedOutputConfigured: Bool {
        shiftedOutputSequence != nil
    }

    /// Whether the current input key has a standard shift symbol (e.g., 1->!, ;->:)
    var defaultShiftSymbol: String? {
        LabelMetadata.forLabel(inputLabel).shiftSymbol
    }

    var shiftedOutputBlockingReason: String? {
        if selectedAppCondition != nil {
            return "Shift output is only available for rules that apply everywhere."
        }
        if selectedApp != nil || selectedSystemAction != nil || selectedURL != nil {
            return "Shift output works only with keystroke output."
        }
        if advancedBehavior.hasAdvancedConfig {
            return "Shift output isn't available with hold, combo, or multi-tap behaviors."
        }
        return nil
    }

    var canUseShiftedOutput: Bool {
        shiftedOutputBlockingReason == nil
    }

    var isIdentityKeystrokeMapping: Bool {
        guard selectedApp == nil,
              selectedSystemAction == nil,
              selectedURL == nil,
              !advancedBehavior.hasAdvancedConfig,
              let inputKanata = currentInputKanataString(),
              let outputSequence
        else {
            return false
        }

        let outputKanata = convertSequenceToKanataFormat(outputSequence)
        return inputKanata.caseInsensitiveCompare(outputKanata) == .orderedSame
    }

    func configure(kanataManager: RuntimeCoordinator) {
        self.kanataManager = kanataManager
        Task {
            await refreshAvailableLayers()
        }
    }

    /// Set the current layer.
    func setLayer(_ layer: String) {
        currentLayer = layer
        AppLogger.shared.log("🗂️ [MapperViewModel] Layer set to: \(layer)")

        NotificationCenter.default.post(
            name: .kanataLayerChanged,
            object: nil,
            userInfo: ["layer": layer]
        )
    }

    /// Update input from a key click in the overlay (used by mapper drawer).
    func setInputFromKeyClick(
        keyCode: UInt16,
        inputLabel: String,
        outputLabel: String,
        appIdentifier: String? = nil,
        systemActionIdentifier: String? = nil,
        urlIdentifier: String? = nil,
        shiftedOutputKey: String? = nil
    ) {
        stopRecording()

        inputKeyCode = keyCode
        self.inputLabel = formatKeyForDisplay(inputLabel)
        inputSequence = KeySequence(
            keys: [KeyPress(baseKey: inputLabel, modifiers: [], keyCode: Int64(keyCode))],
            captureMode: .single
        )

        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil
        selectedAppCondition = nil
        selectedDeviceCondition = nil
        clearShiftedOutput()

        if let appId = appIdentifier, let appInfo = appLaunchInfo(for: appId) {
            selectedApp = appInfo
            self.outputLabel = appInfo.name
            outputSequence = nil
            AppLogger.shared.log("🖱️ [MapperViewModel] Key click - app launch: \(inputLabel) -> \(appInfo.name)")
        } else if let urlId = urlIdentifier {
            selectedURL = urlId
            self.outputLabel = extractDomain(from: urlId)
            outputSequence = nil
            AppLogger.shared.log("🖱️ [MapperViewModel] Key click - URL: \(inputLabel) -> \(urlId)")
        } else if let systemId = systemActionIdentifier, let systemAction = SystemActionInfo.find(byOutput: systemId) {
            selectedSystemAction = systemAction
            self.outputLabel = systemAction.name
            outputSequence = nil
            AppLogger.shared.log("🖱️ [MapperViewModel] Key click - system action: \(inputLabel) -> \(systemAction.name)")
        } else if let systemAction = SystemActionInfo.find(byOutput: outputLabel) {
            selectedSystemAction = systemAction
            self.outputLabel = systemAction.name
            outputSequence = nil
            AppLogger.shared.log("🖱️ [MapperViewModel] Key click - system action (fallback): \(inputLabel) -> \(systemAction.name)")
        } else {
            self.outputLabel = formatKeyForDisplay(outputLabel)
            outputSequence = KeySequence(
                keys: [KeyPress(baseKey: outputLabel, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
            AppLogger.shared.log("🖱️ [MapperViewModel] Key click - key mapping: \(inputLabel) -> \(outputLabel)")
        }
        applyShiftedOutputPreset(shiftedOutputKey)

        if !hasShiftedOutputConfigured, let defaultShift = defaultShiftSymbol {
            shiftedOutputLabel = defaultShift
            shiftedOutputSequence = KeySequence(
                keys: [KeyPress(baseKey: defaultShift, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
            isShiftedOutputDefault = true
        }

        Task { await updateAppsWithMapping() }

        advancedBehavior.holdAction = ""
        advancedBehavior.doubleTapAction = ""
        advancedBehavior.macroBehavior = nil
        advancedBehavior.comboKeys = []
        advancedBehavior.comboOutput = ""
        advancedBehavior.holdBehavior = .basic
        advancedBehavior.tapTimeout = 200
        advancedBehavior.holdTimeout = 200
        advancedBehavior.customTapKeysText = ""
    }

    /// Load behavior from existing custom rule for the current input key.
    func loadBehaviorFromExistingRule(kanataManager: RuntimeCoordinator) {
        guard let keyCode = inputKeyCode else { return }
        let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)

        guard let existingRule = kanataManager.getCustomRule(forInput: inputKey) else {
            if !hasShiftedOutputConfigured, let defaultShift = defaultShiftSymbol {
                shiftedOutputLabel = defaultShift
                shiftedOutputSequence = KeySequence(
                    keys: [KeyPress(baseKey: defaultShift, modifiers: [], keyCode: 0)],
                    captureMode: .single
                )
                isShiftedOutputDefault = true
            }
            AppLogger.shared.log("📖 [MapperViewModel] No existing behavior for input '\(inputKey)'")
            return
        }
        applyShiftedOutputPreset(existingRule.shiftedOutput)
        if hasShiftedOutputConfigured {
            isShiftedOutputDefault = false
        } else if let defaultShift = defaultShiftSymbol {
            shiftedOutputLabel = defaultShift
            shiftedOutputSequence = KeySequence(
                keys: [KeyPress(baseKey: defaultShift, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
            isShiftedOutputDefault = true
        }

        guard let behavior = existingRule.behavior else {
            AppLogger.shared.log("📖 [MapperViewModel] No existing behavior for input '\(inputKey)'")
            return
        }

        switch behavior {
        case let .dualRole(dualRole):
            advancedBehavior.holdAction = dualRole.holdActionString
            advancedBehavior.tapTimeout = dualRole.tapTimeout
            advancedBehavior.holdTimeout = dualRole.holdTimeout

            if dualRole.activateHoldOnOtherKey {
                advancedBehavior.holdBehavior = .triggerEarly
            } else if dualRole.quickTap {
                advancedBehavior.holdBehavior = .quickTap
            } else if !dualRole.customTapKeys.isEmpty {
                advancedBehavior.holdBehavior = .customKeys
                advancedBehavior.customTapKeysText = dualRole.customTapKeys.joined(separator: " ")
            } else {
                advancedBehavior.holdBehavior = .basic
            }

            AppLogger.shared.log("📖 [MapperViewModel] Loaded dualRole behavior for '\(inputKey)': hold='\(dualRole.holdAction)'")

        case let .tapOrTapDance(tapBehavior):
            switch tapBehavior {
            case .tap:
                AppLogger.shared.log("📖 [MapperViewModel] Loaded tap behavior for '\(inputKey)'")
            case let .tapDance(tapDance):
                advancedBehavior.tapTimeout = tapDance.windowMs
                if tapDance.steps.count > 1 {
                    advancedBehavior.doubleTapAction = tapDance.steps[1].actionString
                }
                if tapDance.steps.count > 2 {
                    advancedBehavior.tapDanceSteps = tapDance.steps.dropFirst(2).map { step in
                        (label: step.label, action: step.actionString, isRecording: false)
                    }
                }

                AppLogger.shared.log("📖 [MapperViewModel] Loaded tapDance behavior for '\(inputKey)': \(tapDance.steps.count) steps, windowMs=\(tapDance.windowMs)")
            }

        case let .macro(macro):
            advancedBehavior.macroBehavior = macro
            AppLogger.shared.log("📖 [MapperViewModel] Loaded macro behavior for '\(inputKey)'")

        case let .chord(chord):
            advancedBehavior.comboKeys = chord.keys.filter { $0.lowercased() != inputKey.lowercased() }
            advancedBehavior.comboOutput = chord.outputString
            advancedBehavior.comboTimeout = chord.timeout

            AppLogger.shared.log("📖 [MapperViewModel] Loaded chord behavior for '\(inputKey)': keys=\(chord.keys), output='\(chord.outputString)'")
        }
    }

    /// Update the list of apps that have a mapping for the currently selected input key.
    func updateAppsWithMapping() async {
        guard let keyCode = inputKeyCode else {
            appsWithCurrentKeyMapping = []
            return
        }
        let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)
        appsWithCurrentKeyMapping = await AppKeymapStore.shared.getAppsWithMapping(forInputKey: inputKey)
    }

    /// Apply preset values from overlay click.
    func applyPresets(
        input: String,
        output: String,
        layer: String? = nil,
        inputKeyCode: UInt16? = nil,
        appIdentifier: String? = nil,
        systemActionIdentifier: String? = nil,
        urlIdentifier: String? = nil,
        shiftedOutput: String? = nil
    ) {
        stopRecording()

        originalInputKey = input
        originalOutputKey = output
        originalShiftedOutputKey = shiftedOutput
        originalAppIdentifier = appIdentifier
        originalSystemActionIdentifier = systemActionIdentifier
        originalURL = urlIdentifier
        originalLayer = layer

        lastSavedRuleID = nil
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil
        clearShiftedOutput()

        if let layer {
            currentLayer = layer
        }

        inputLabel = formatKeyForDisplay(input)
        let keyCodeToUse = inputKeyCode ?? 0
        inputSequence = KeySequence(
            keys: [KeyPress(baseKey: input, modifiers: [], keyCode: Int64(keyCodeToUse))],
            captureMode: .single
        )

        if let appIdentifier, let appInfo = appLaunchInfo(for: appIdentifier) {
            selectedApp = appInfo
            outputLabel = appInfo.name
            outputSequence = nil
            AppLogger.shared.log("🗺️ [MapperViewModel] Preset output is app launch: \(appInfo.name)")
        } else if let urlIdentifier {
            selectedURL = urlIdentifier
            outputLabel = extractDomain(from: urlIdentifier)
            outputSequence = nil
            AppLogger.shared.log("🗺️ [MapperViewModel] Preset output is URL: \(urlIdentifier)")
        } else if let systemActionIdentifier,
                  let systemAction = SystemActionInfo.find(byOutput: systemActionIdentifier)
        {
            selectedSystemAction = systemAction
            outputLabel = systemAction.name
            outputSequence = nil
            AppLogger.shared.log("🗺️ [MapperViewModel] Preset output is system action: \(systemAction.name)")
        } else if let systemAction = SystemActionInfo.find(byOutput: output) {
            selectedSystemAction = systemAction
            outputLabel = systemAction.name
            outputSequence = nil
            AppLogger.shared.log("🗺️ [MapperViewModel] Preset output is system action: \(systemAction.name)")
        } else {
            outputLabel = formatKeyForDisplay(output)
            outputSequence = KeySequence(
                keys: [KeyPress(baseKey: output, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
        }
        applyShiftedOutputPreset(shiftedOutput)

        if let inputKeyCode {
            self.inputKeyCode = inputKeyCode
        }

        statusMessage = nil
        statusIsError = false

        AppLogger.shared.log("📝 [MapperViewModel] Applied presets: \(input) → \(output) [layer: \(currentLayer)] [inputKeyCode: \(keyCodeToUse)]")
    }

    /// Format a kanata key name for display (e.g., "leftmeta" -> "cmd").
    func formatKeyForDisplay(_ key: String) -> String {
        AppLogger.shared.log("🔤 [MapperViewModel] formatKeyForDisplay input: '\(key)'")
        let result = KeyDisplayFormatter.format(key)
        AppLogger.shared.log("🔤 [MapperViewModel] formatKeyForDisplay output: '\(result)'")
        return result
    }

    func formattedSequenceForDisplay(_ sequence: String) -> String {
        sequence
            .split(separator: " ")
            .map { formatKeyForDisplay(String($0)) }
            .joined(separator: " ")
    }

    func applyShiftedOutputPreset(_ shiftedOutput: String?) {
        guard let shiftedOutput = shiftedOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
              !shiftedOutput.isEmpty
        else {
            clearShiftedOutput()
            return
        }

        originalShiftedOutputKey = shiftedOutput
        shiftedOutputLabel = formattedSequenceForDisplay(shiftedOutput)
        shiftedOutputSequence = KeySequence(
            keys: [KeyPress(baseKey: shiftedOutput, modifiers: [], keyCode: 0)],
            captureMode: .single
        )
        isShiftedOutputDefault = false
    }
}
