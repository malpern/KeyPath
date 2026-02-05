import Foundation
import KeyPathCore

extension MapperViewModel {
    // MARK: - Multi-Tap Helpers

    func multiTapAction(for count: Int) -> String? {
        guard count >= 2 else { return nil }
        if count == 2 {
            return doubleTapAction.isEmpty ? nil : doubleTapAction
        }

        let index = count - 3
        guard index >= 0, index < tapDanceSteps.count else { return nil }
        let action = tapDanceSteps[index].action
        return action.isEmpty ? nil : action
    }

    func setMultiTapAction(_ action: String?, for count: Int) {
        guard count >= 2 else { return }

        if count == 2 {
            doubleTapAction = action ?? ""
            return
        }

        let index = count - 3
        ensureTapDanceStepIndex(index)
        tapDanceSteps[index].action = action ?? ""
        trimTrailingEmptyTapDanceSteps()
    }

    func isRecordingMultiTap(for count: Int) -> Bool {
        guard count >= 2 else { return false }
        if count == 2 {
            return isRecordingDoubleTap
        }
        let index = count - 3
        guard index >= 0, index < tapDanceSteps.count else { return false }
        return tapDanceSteps[index].isRecording
    }

    func toggleMultiTapRecording(for count: Int) {
        guard count >= 2 else { return }
        if count == 2 {
            toggleDoubleTapRecording()
        } else {
            let index = count - 3
            ensureTapDanceStepIndex(index)
            toggleTapDanceRecording(at: index)
        }
    }

    func clearMultiTapAction(for count: Int) {
        guard count >= 2 else { return }
        if count == 2 {
            doubleTapAction = ""
        } else {
            let index = count - 3
            guard index >= 0, index < tapDanceSteps.count else { return }
            tapDanceSteps[index].action = ""
            trimTrailingEmptyTapDanceSteps()
        }
    }

    private func ensureTapDanceStepIndex(_ index: Int) {
        guard index >= 0 else { return }
        while tapDanceSteps.count <= index {
            let nextIndex = tapDanceSteps.count
            guard nextIndex < Self.tapDanceLabels.count else { return }
            let label = Self.tapDanceLabels[nextIndex]
            tapDanceSteps.append((label: label, action: "", isRecording: false))
        }
    }

    private func trimTrailingEmptyTapDanceSteps() {
        while let last = tapDanceSteps.last, last.action.isEmpty {
            tapDanceSteps.removeLast()
        }
    }

    static func keyOutputFromPress(_ press: KeyPress) -> String {
        var prefix = ""
        if press.modifiers.contains(.command) { prefix += "M-" }
        if press.modifiers.contains(.control) { prefix += "C-" }
        if press.modifiers.contains(.option) { prefix += "A-" }
        if press.modifiers.contains(.shift) { prefix += "S-" }
        return prefix + press.baseKey
    }

    /// Clear tap-dance step action at index
    func clearTapDanceStep(at index: Int) {
        advancedBehavior.clearTapDanceStep(at: index)
    }

}
