import KeyPathCore
import SwiftUI

extension OverlayMapperSection {
    // MARK: - Computed Properties for Selected Slot

    /// The display label for the currently selected behavior slot's output
    /// Returns the configured action, or empty string if not configured
    var currentSlotOutputLabel: String {
        switch selectedBehaviorSlot {
        case .tap:
            return viewModel.outputLabel
        case .hold:
            let action = viewModel.holdAction
            return action.isEmpty ? "" : KeyDisplayFormatter.format(action)
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
            // Tap always has a behavior (even if it's same key in/out)
            true
        case .hold:
            !viewModel.holdAction.isEmpty
        case .combo:
            viewModel.advancedBehavior.hasValidCombo
        }
    }

    /// Whether we're currently recording for the selected slot
    var isRecordingForCurrentSlot: Bool {
        switch selectedBehaviorSlot {
        case .tap:
            viewModel.isRecordingOutput
        case .hold:
            viewModel.isRecordingHold
        case .combo:
            viewModel.isRecordingComboOutput
        }
    }

    /// Whether any recording mode is active (for ESC cancel)
    var isAnyRecordingActive: Bool {
        viewModel.isRecordingInput ||
            viewModel.isRecordingOutput ||
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
