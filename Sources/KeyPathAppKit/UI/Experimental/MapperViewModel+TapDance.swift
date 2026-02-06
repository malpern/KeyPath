import Foundation

extension MapperViewModel {
    // MARK: - Tap-Dance Steps (Triple, Quad, etc.)

    /// Add next tap-dance step (Triple Tap, Quad Tap, etc.)
    func addTapDanceStep() {
        advancedBehavior.addTapDanceStep()
    }

    /// Remove tap-dance step at index
    func removeTapDanceStep(at index: Int) {
        advancedBehavior.removeTapDanceStep(at: index)
    }

    /// Toggle recording for tap-dance step at index
    func toggleTapDanceRecording(at index: Int) {
        guard index >= 0, index < tapDanceSteps.count else { return }

        // Clear macro if needed
        if macroBehavior?.isValid == true {
            macroBehavior = nil
        }

        // Check for conflict: if hold is set, show conflict dialog
        if advancedBehavior.checkTapDanceConflict() {
            pendingConflictType = .holdVsTapDance
            pendingConflictField = "tapDance-\(index)"
            showConflictDialog = true
            return
        }

        if tapDanceSteps[index].isRecording {
            tapDanceSteps[index].isRecording = false
            stopMultiTapSequenceCapture(finalize: true)
        } else {
            // Stop any other recording
            stopRecording()
            stopAllRecording()
            tapDanceSteps[index].isRecording = true
            startMultiTapSequenceCapture(
                onUpdate: { [weak self] action in
                    guard let self, index < tapDanceSteps.count else { return }
                    tapDanceSteps[index].action = action
                },
                onFinalize: { [weak self] action in
                    guard let self, index < tapDanceSteps.count else { return }
                    tapDanceSteps[index].action = action
                },
                onStop: { [weak self] in
                    guard let self, index < tapDanceSteps.count else { return }
                    tapDanceSteps[index].isRecording = false
                }
            )
        }
    }

}
