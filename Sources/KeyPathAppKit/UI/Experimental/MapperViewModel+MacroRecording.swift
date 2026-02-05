import Foundation
import KeyPathCore

extension MapperViewModel {
    // MARK: - Macro Recording

    func toggleMacroRecording() {
        if isRecordingMacro {
            stopMacroRecording()
            return
        }

        // Clear hold/tap-dance when starting macro
        if checkHoldConflict() {
            clearHoldAndTapDanceForMacro()
        }

        startMacroRecording()
    }

    func clearMacro() {
        macroBehavior = nil
    }

    private func startMacroRecording() {
        stopRecording()
        isRecordingMacro = true
        savedMacroBehavior = macroBehavior

        if keyboardCapture == nil {
            keyboardCapture = KeyboardCapture()
        }

        guard let capture = keyboardCapture else {
            isRecordingMacro = false
            return
        }

        capture.startSequenceCapture(mode: .sequence) { [weak self] sequence in
            guard let self else { return }

            Task { @MainActor in
                let outputs = sequence.keys.map { Self.keyOutputFromPress($0) }
                macroBehavior = MacroBehavior(outputs: outputs, source: .keys)

                self.finalizeTimer?.invalidate()
                self.finalizeTimer = Timer.scheduledTimer(
                    withTimeInterval: self.sequenceFinalizeDelay,
                    repeats: false
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.stopMacroRecording()
                    }
                }
            }
        }
    }

    private func stopMacroRecording() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        keyboardCapture?.stopCapture()
        isRecordingMacro = false

        if macroBehavior == nil || macroBehavior?.effectiveOutputs.isEmpty == true {
            macroBehavior = savedMacroBehavior
        }
        savedMacroBehavior = nil
    }

    private func clearHoldAndTapDanceForMacro() {
        holdAction = ""
        holdBehavior = .basic
        customTapKeysText = ""
        doubleTapAction = ""
        tapDanceSteps.removeAll()
    }

}
