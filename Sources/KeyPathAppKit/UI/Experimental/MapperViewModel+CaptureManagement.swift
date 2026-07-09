import AppKit
import Foundation
import KeyPathCore

// MARK: - Capture Management

extension MapperViewModel {
    /// Simple single-key capture for hold/double-tap/tap-dance actions
    func startSimpleKeyCapture(onCapture: @escaping (String) -> Void) {
        stopSimpleKeyCapture()
        let token = UUID()
        simpleKeyCaptureToken = token
        simpleKeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Escape cancels recording
            if event.keyCode == 53 {
                self?.stopAllRecording()
                return nil
            }

            let keyName = Self.keyNameFromEvent(event)
            onCapture(keyName)
            self?.stopSimpleKeyCapture()
            return nil
        }

        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            guard simpleKeyCaptureToken == token else { return }
            let isAnyRecording = isRecordingHold || isRecordingDoubleTap || tapDanceSteps.contains { $0.isRecording }
            if isAnyRecording {
                stopAllRecording()
            }
        }
    }

    func startMultiTapSequenceCapture(
        onUpdate: @escaping (String) -> Void,
        onFinalize: @escaping (String) -> Void,
        onStop: @escaping () -> Void
    ) {
        stopMultiTapSequenceCapture(finalize: false)
        multiTapUpdateHandler = onUpdate
        multiTapFinalizeHandler = onFinalize
        multiTapStopHandler = onStop
        multiTapPendingSequence = nil

        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
        }

        guard let capture = keyboardCapture else {
            AppLogger.shared.error("❌ [MapperViewModel] Failed to create KeyboardCapture for multi-tap")
            stopMultiTapSequenceCapture(finalize: false)
            return
        }

        capture.startSequenceCapture(mode: .sequence) { [weak self] sequence in
            guard let self else { return }
            let viewModel = self

            Task { @MainActor [weak viewModel] in
                guard let viewModel else { return }
                viewModel.multiTapPendingSequence = sequence
                let action = viewModel.convertSequenceToKanataFormat(sequence)
                viewModel.multiTapUpdateHandler?(action)
                viewModel.multiTapFinalizeTimer?.invalidate()
                viewModel.multiTapFinalizeTimer = Timer.scheduledTimer(
                    withTimeInterval: viewModel.sequenceFinalizeDelay,
                    repeats: false
                ) { [weak viewModel] _ in
                    Task { @MainActor in
                        viewModel?.finalizeMultiTapSequence()
                    }
                }
            }
        }
    }

    func finalizeMultiTapSequence() {
        multiTapFinalizeTimer?.invalidate()
        multiTapFinalizeTimer = nil
        keyboardCapture?.stopCapture()

        defer {
            multiTapUpdateHandler = nil
            multiTapFinalizeHandler = nil
            multiTapStopHandler = nil
            multiTapPendingSequence = nil
        }

        guard let sequence = multiTapPendingSequence else {
            multiTapStopHandler?()
            return
        }

        let action = convertSequenceToKanataFormat(sequence)
        multiTapFinalizeHandler?(action)
        multiTapStopHandler?()
    }

    func stopMultiTapSequenceCapture(finalize: Bool) {
        if finalize {
            finalizeMultiTapSequence()
            return
        }

        multiTapFinalizeTimer?.invalidate()
        multiTapFinalizeTimer = nil
        keyboardCapture?.stopCapture()
        multiTapStopHandler?()
        multiTapUpdateHandler = nil
        multiTapFinalizeHandler = nil
        multiTapStopHandler = nil
        multiTapPendingSequence = nil
    }

    /// Stop all recording states
    func stopAllRecording() {
        stopSimpleKeyCapture()
        stopMultiTapSequenceCapture(finalize: false)
        advancedBehavior.stopAllRecording()
    }

    func stopSimpleKeyCapture() {
        if let monitor = simpleKeyCaptureMonitor {
            NSEvent.removeMonitor(monitor)
        }
        simpleKeyCaptureMonitor = nil
        simpleKeyCaptureToken = nil
    }

    /// Convert key event to kanata key name
    static func keyNameFromEvent(_ event: NSEvent) -> String {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags

        var prefix = ""
        if modifiers.contains(.command) { prefix += "M-" }
        if modifiers.contains(.control) { prefix += "C-" }
        if modifiers.contains(.option) { prefix += "A-" }
        if modifiers.contains(.shift) { prefix += "S-" }

        let keyName = switch keyCode {
        case 0: "a"
        case 1: "s"
        case 2: "d"
        case 3: "f"
        case 4: "h"
        case 5: "g"
        case 6: "z"
        case 7: "x"
        case 8: "c"
        case 9: "v"
        case 11: "b"
        case 12: "q"
        case 13: "w"
        case 14: "e"
        case 15: "r"
        case 16: "y"
        case 17: "t"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "="
        case 25: "9"
        case 26: "7"
        case 27: "-"
        case 28: "8"
        case 29: "0"
        case 30: "]"
        case 31: "o"
        case 32: "u"
        case 33: "["
        case 34: "i"
        case 35: "p"
        case 36: "ret"
        case 37: "l"
        case 38: "j"
        case 39: "'"
        case 40: "k"
        case 41: ";"
        case 42: "\\"
        case 43: ","
        case 44: "/"
        case 45: "n"
        case 46: "m"
        case 47: "."
        case 48: "tab"
        case 49: "spc"
        case 50: "`"
        case 51: "bspc"
        case 53: "esc"
        case 55: "lmet"
        case 56: "lsft"
        case 57: "caps"
        case 58: "lalt"
        case 59: "lctl"
        case 60: "rsft"
        case 61: "ralt"
        case 62: "rctl"
        case 63: "fn"
        case 96: "f5"
        case 97: "f6"
        case 98: "f7"
        case 99: "f3"
        case 100: "f8"
        case 101: "f9"
        case 103: "f11"
        case 105: "f13"
        case 107: "f14"
        case 109: "f10"
        case 111: "f12"
        case 113: "f15"
        case 118: "f4"
        case 119: "end"
        case 120: "f2"
        case 121: "pgdn"
        case 122: "f1"
        case 123: "left"
        case 124: "right"
        case 125: "down"
        case 126: "up"
        default: "k\(keyCode)"
        }

        return prefix + keyName
    }

    func startInputRecording() {
        isRecordingInput = true
        inputSequence = nil
        inputKeyCode = nil
        inputLabel = "..."
        statusMessage = "Press keys (sequence supported)"
        statusIsError = false
        startCapture(target: .input)
    }

    func startOutputRecording() {
        // Save current output state before recording (for restore on cancel)
        savedOutputLabel = outputLabel
        savedOutputSequence = outputSequence
        savedSelectedApp = selectedApp
        savedSelectedSystemAction = selectedSystemAction

        isRecordingOutput = true
        outputSequence = nil
        outputLabel = "..."
        // Clear system action/app so keycap shows recording state
        selectedSystemAction = nil
        selectedApp = nil
        statusMessage = "Press keys (sequence supported)"
        statusIsError = false
        startCapture(target: .output)
    }

    func startShiftedOutputRecording() {
        guard canUseShiftedOutput else {
            statusMessage = shiftedOutputBlockingReason
            statusIsError = true
            return
        }

        savedShiftedOutputLabel = shiftedOutputLabel
        savedShiftedOutputSequence = shiftedOutputSequence

        isRecordingShiftedOutput = true
        shiftedOutputLabel = "..."
        shiftedOutputSequence = nil
        statusMessage = "Press keys for Shift output"
        statusIsError = false
        startCapture(target: .shiftedOutput)
    }

    func startCapture(target: CaptureTarget) {
        // Create keyboard capture if needed
        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
        }

        guard let capture = keyboardCapture else {
            AppLogger.shared.error("❌ [MapperViewModel] Failed to create KeyboardCapture")
            stopRecording()
            return
        }

        // Use sequence mode for multi-key support
        capture.startSequenceCapture(mode: .sequence) { [weak self] sequence in
            guard let self else { return }
            let viewModel = self

            Task { @MainActor [weak viewModel] in
                guard let viewModel else { return }
                // Update the captured sequence (streaming updates)
                if target == .input {
                    viewModel.inputSequence = sequence
                    viewModel.inputLabel = sequence.displayString
                    // Store first key's keyCode for overlay-style rendering
                    // Guard against negative keyCodes (e.g., -1 for modifier-only keys or unknown keys)
                    if let firstKey = sequence.keys.first,
                       firstKey.keyCode >= 0,
                       firstKey.keyCode <= Int64(UInt16.max)
                    {
                        let keyCode = UInt16(firstKey.keyCode)
                        viewModel.inputKeyCode = keyCode

                        // Look up current mapping for this key and update output
                        viewModel.lookupAndSetOutput(forKeyCode: keyCode)
                    }
                } else if target == .shiftedOutput {
                    viewModel.shiftedOutputSequence = sequence
                    viewModel.shiftedOutputLabel = sequence.displayString
                } else {
                    viewModel.outputSequence = sequence
                    viewModel.outputLabel = sequence.displayString
                }

                // Reset finalize timer - wait for more keys
                viewModel.finalizeTimer?.invalidate()
                viewModel.finalizeTimer = Timer.scheduledTimer(
                    withTimeInterval: viewModel.sequenceFinalizeDelay,
                    repeats: false
                ) { [weak viewModel] _ in
                    Task { @MainActor in
                        viewModel?.finalizeCapture()
                    }
                }
            }
        }
    }

    /// Look up the current output for a key code from the overlay's layer map
    func lookupAndSetOutput(forKeyCode keyCode: UInt16) {
        // Clear any selected app/system action since we're switching keys
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil
        clearShiftedOutput()

        let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)

        // Look up the current mapping from the overlay controller
        if let mapping = LiveKeyboardOverlayController.shared.lookupCurrentMapping(forKeyCode: keyCode) {
            let info = mapping.info

            if let appIdentifier = info.appLaunchIdentifier,
               let appInfo = appLaunchInfo(for: appIdentifier)
            {
                selectedApp = appInfo
                outputLabel = appInfo.name
                outputSequence = nil
                originalAppIdentifier = appIdentifier
                originalSystemActionIdentifier = nil
                originalURL = nil
                originalShiftedOutputKey = nil
                AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) is app launch: \(appInfo.name)")
            } else if let url = info.urlIdentifier {
                selectedURL = url
                outputLabel = extractDomain(from: url)
                outputSequence = nil
                originalURL = url
                originalAppIdentifier = nil
                originalSystemActionIdentifier = nil
                originalShiftedOutputKey = nil
                AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) is URL: \(url)")
            } else if let systemId = info.systemActionIdentifier,
                      let systemAction = SystemActionInfo.find(byOutput: systemId) ?? SystemActionInfo.find(byOutput: info.displayLabel)
            {
                selectedSystemAction = systemAction
                outputLabel = systemAction.name
                outputSequence = nil
                originalSystemActionIdentifier = systemId
                originalAppIdentifier = nil
                originalURL = nil
                originalShiftedOutputKey = nil
                AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) is system action: \(systemAction.name)")
            } else if let outputKey = info.outputKey {
                outputLabel = formatKeyForDisplay(outputKey)
                outputSequence = KeySequence(
                    keys: [KeyPress(baseKey: outputKey, modifiers: [], keyCode: 0)],
                    captureMode: .single
                )
                originalAppIdentifier = nil
                originalSystemActionIdentifier = nil
                originalURL = nil
                originalShiftedOutputKey = nil
            } else {
                // Fallback: use displayLabel as the output key
                outputLabel = info.displayLabel
                let outputKey = info.displayLabel.lowercased()
                outputSequence = KeySequence(
                    keys: [KeyPress(baseKey: outputKey, modifiers: [], keyCode: 0)],
                    captureMode: .single
                )
                originalAppIdentifier = nil
                originalSystemActionIdentifier = nil
                originalURL = nil
                originalShiftedOutputKey = nil
            }

            // Store original context for reset
            originalInputKey = inputKey
            originalOutputKey = info.outputKey ?? info.displayLabel
            originalLayer = mapping.layer
            currentLayer = mapping.layer

            AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) maps to: \(outputLabel) in layer \(currentLayer)")
        } else {
            // No mapping found - default to key maps to itself
            outputLabel = formatKeyForDisplay(inputKey)
            outputSequence = KeySequence(
                keys: [KeyPress(baseKey: inputKey, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
            originalInputKey = inputKey
            originalOutputKey = inputKey
            originalShiftedOutputKey = nil
        }
    }

    func finalizeCapture() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil

        // Stop recording but keep the captured sequence
        keyboardCapture?.stopCapture()
        isRecordingInput = false
        isRecordingOutput = false
        isRecordingShiftedOutput = false
        statusMessage = nil

        AppLogger.shared.log("🎯 [MapperViewModel] finalizeCapture: canSave=\(canSave) selectedApp=\(selectedApp?.name ?? "nil") inputSeq=\(inputSequence?.displayString ?? "nil")")

        // Auto-save when input is captured and we have either output or app/system action/URL/folder/script
        if canSave, let manager = kanataManager {
            Task {
                if selectedURL != nil {
                    AppLogger.shared.log("🎯 [MapperViewModel] Calling saveURLMapping")
                    await saveURLMapping(kanataManager: manager)
                } else if selectedApp != nil {
                    AppLogger.shared.log("🎯 [MapperViewModel] Calling saveAppLaunchMapping")
                    await saveAppLaunchMapping(kanataManager: manager)
                } else if selectedSystemAction != nil {
                    AppLogger.shared.log("🎯 [MapperViewModel] Calling saveSystemActionMapping")
                    await saveSystemActionMapping(kanataManager: manager)
                } else if selectedFolder != nil {
                    AppLogger.shared.log("🎯 [MapperViewModel] Calling saveFolderMapping")
                    await saveFolderMapping(kanataManager: manager)
                } else if selectedScript != nil {
                    AppLogger.shared.log("🎯 [MapperViewModel] Calling saveScriptMapping")
                    await saveScriptMapping(kanataManager: manager)
                } else {
                    await save(kanataManager: manager)
                }
            }
        }
    }

    func stopRecording() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        keyboardCapture?.stopCapture()

        let wasRecordingOutput = isRecordingOutput
        let wasRecordingShiftedOutput = isRecordingShiftedOutput
        let wasRecordingMacro = isRecordingMacro
        isRecordingInput = false
        isRecordingOutput = false
        isRecordingShiftedOutput = false
        isRecordingMacro = false

        // If we stopped without capturing anything, restore previous state
        if inputSequence == nil {
            inputLabel = "A"
            inputKeyCode = 0 // Default to A key
        }

        // For output: restore saved state if nothing was captured during this recording session
        if wasRecordingOutput, outputSequence == nil {
            // Restore previous output state
            if let savedLabel = savedOutputLabel {
                outputLabel = savedLabel
                outputSequence = savedOutputSequence
                selectedApp = savedSelectedApp
                selectedSystemAction = savedSelectedSystemAction
            } else {
                // No saved state, default to "A"
                outputLabel = "A"
            }
        }

        if wasRecordingShiftedOutput, shiftedOutputSequence == nil {
            shiftedOutputLabel = savedShiftedOutputLabel
            shiftedOutputSequence = savedShiftedOutputSequence
        }

        // Clear saved state
        savedOutputLabel = nil
        savedOutputSequence = nil
        savedShiftedOutputLabel = nil
        savedShiftedOutputSequence = nil
        savedSelectedApp = nil
        savedSelectedSystemAction = nil

        if wasRecordingMacro {
            if macroBehavior == nil || macroBehavior?.effectiveOutputs.isEmpty == true {
                macroBehavior = savedMacroBehavior
            }
            savedMacroBehavior = nil
        }

        statusMessage = nil
    }

    func stopKeyCapture() {
        stopRecording()
        keyboardCapture = nil
    }
}
