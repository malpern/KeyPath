import AppKit
import Foundation
import KeyPathCore

extension MapperViewModel {
    enum CaptureTarget {
        case input
        case output
        case shiftedOutput
    }

    // MARK: - Conflict Resolution

    /// Resolve conflict by keeping hold (clears all tap-dance actions)
    func resolveConflictKeepHold() {
        // If user was trying to record hold, we need to start that recording after clearing
        let field = pendingConflictField

        advancedBehavior.resolveConflictKeepHold()

        if field == "hold" {
            // Now safe to record hold
            stopRecording()
            isRecordingHold = true
            startSimpleKeyCapture { [weak self] keyName in
                self?.holdAction = keyName
                self?.isRecordingHold = false
            }
        }
    }

    /// Resolve conflict by keeping tap-dance (clears hold action)
    func resolveConflictKeepTapDance() {
        advancedBehavior.resolveConflictKeepTapDance()

        // Now start recording in the originally attempted field
        let field = pendingConflictField
        pendingConflictType = nil
        pendingConflictField = ""

        if field == "doubleTap" {
            toggleDoubleTapRecording()
        } else if field.hasPrefix("tapDance-"), let index = Int(field.replacingOccurrences(of: "tapDance-", with: "")) {
            toggleTapDanceRecording(at: index)
        }
    }

    /// Check if hold action has conflict with existing tap-dance
    func checkHoldConflict() -> Bool {
        advancedBehavior.checkHoldConflict()
    }
}
