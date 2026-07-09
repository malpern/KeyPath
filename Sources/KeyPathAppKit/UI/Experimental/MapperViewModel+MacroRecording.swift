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
            let viewModel = self

            Task { @MainActor [weak viewModel] in
                guard let viewModel else { return }
                let outputs = sequence.keys.map { Self.keyOutputFromPress($0) }
                viewModel.macroBehavior = MacroBehavior(outputs: outputs, source: .keys)

                viewModel.finalizeTimer?.invalidate()
                viewModel.finalizeTimer = Timer.scheduledTimer(
                    withTimeInterval: viewModel.sequenceFinalizeDelay,
                    repeats: false
                ) { [weak viewModel] _ in
                    Task { @MainActor in
                        viewModel?.stopMacroRecording()
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
