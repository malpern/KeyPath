import KeyPathCore
import SwiftUI

extension OverlayMapperSection {
    // MARK: - Computed Properties for Selected Slot

    /// The display label for the currently selected behavior slot's output
    /// Returns the configured action, or empty string if not configured
    var currentSlotOutputLabel: String {
        switch selectedBehaviorSlot {
        case .tap:
            if selectedTapCount > 1 {
                let action = viewModel.multiTapAction(for: selectedTapCount) ?? ""
                return action.isEmpty ? "" : KeyDisplayFormatter.format(action)
            }
            return activeTapOutputLabel
        case .hold:
            let action = viewModel.holdAction
            return action.isEmpty ? "" : KeyDisplayFormatter.format(action)
        case .shift:
            return viewModel.shiftedOutputLabel ?? ""
        case .combo:
            let action = viewModel.comboOutput
            return action.isEmpty ? "" : KeyDisplayFormatter.format(action)
        }
    }

    /// Whether the current slot has an action configured
    /// Hold/Combo are optional behaviors that must be explicitly added
    var currentSlotIsConfigured: Bool {
        switch selectedBehaviorSlot {
        case .tap:
            if selectedTapCount > 1 {
                return viewModel.multiTapAction(for: selectedTapCount) != nil
            }
            // Tap always has a behavior (even if it's same key in/out)
            return true
        case .hold:
            return !viewModel.holdAction.isEmpty
        case .shift:
            return viewModel.hasShiftedOutputConfigured && !viewModel.isShiftedOutputDefault
        case .combo:
            return viewModel.advancedBehavior.hasValidCombo
        }
    }

    /// Whether we're currently recording for the selected slot
    var isRecordingForCurrentSlot: Bool {
        switch selectedBehaviorSlot {
        case .tap:
            if selectedTapCount > 1 {
                return viewModel.isRecordingMultiTap(for: selectedTapCount)
            }
            return activeTapIsRecording
        case .hold:
            return viewModel.isRecordingHold
        case .shift:
            return viewModel.isRecordingShiftedOutput
        case .combo:
            return viewModel.isRecordingComboOutput
        }
    }

    /// Whether any recording mode is active (for ESC cancel)
    var isAnyRecordingActive: Bool {
        viewModel.isRecordingInput ||
            viewModel.isRecordingOutput ||
            viewModel.isRecordingShiftedOutput ||
            viewModel.isRecordingHold ||
            viewModel.isRecordingDoubleTap ||
            viewModel.isRecordingComboOutput
    }

    /// Cancel all active recording modes
    func cancelAllRecording() {
        viewModel.stopRecording()
        viewModel.stopAllRecording()
    }
}
