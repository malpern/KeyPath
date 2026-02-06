import AppKit
import KeyPathCore
import SwiftUI

// MARK: - Save, Recording, Validation

extension ContentView {
    func debouncedSave() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceDelay, repeats: false) {
            _ in
            Task { await performSave() }
        }
    }

    func performSave() async {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil

        // Check running state via KanataService
        var serviceState = await kanataManager.currentServiceState()

        // If Kanata is not running but we're recording, stop recording first (resumes Kanata)
        if !serviceState.isRunning,
           recordingCoordinator.isInputRecording() || recordingCoordinator.isOutputRecording() {
            AppLogger.shared.log("🔄 [ContentView] Kanata paused during recording - resuming before save")
            await MainActor.run {
                recordingCoordinator.stopAllRecording()
            }

            // Wait briefly for Kanata to resume
            try? await Task.sleep(for: .milliseconds(500)) // 500ms
            serviceState = await kanataManager.currentServiceState()
        }

        // Pre-flight check: Ensure kanata is running before attempting save
        guard serviceState.isRunning else {
            AppLogger.shared.log("⚠️ [ContentView] Cannot save - kanata service is not running")
            await MainActor.run {
                showingKanataNotRunningAlert = true
            }
            return
        }

        await recordingCoordinator.saveMapping(
            kanataManager: kanataManager.underlyingManager, // Phase 4: Business logic needs underlying manager
            onSuccess: { message in handleSaveSuccess(message) },
            onError: { error in handleSaveError(error) }
        )
    }

    func handleSaveSuccess(_ message: String) {
        showStatusMessage(message: message)
    }

    func handleSaveError(_ error: Error) {
        // Handle coordination errors - invalid state (missing input/output)
        if case KeyPathError.coordination(.invalidState) = error {
            showStatusMessage(message: "❌ Please capture both input and output keys first")
            return
        }

        // Handle coordination errors - recording failed (validation errors like self-reference)
        if case let KeyPathError.coordination(.recordingFailed(reason)) = error {
            showStatusMessage(message: "❌ Recording failed: \(reason)")
            return
        }

        // Handle TCP connectivity errors (before config validation to avoid false positives)
        if case let KeyPathError.configuration(.loadFailed(reason)) = error {
            let reasonLower = reason.lowercased()
            if reasonLower.contains("tcp"),
               reasonLower.contains("required") || reasonLower.contains("unresponsive")
               || reasonLower.contains("failed") || reasonLower.contains("reload") {
                // TCP connectivity issues - open wizard directly to Communication page
                showStatusMessage(message: "⚠️ Service connection failed - opening setup wizard...")
                Task { @MainActor in
                    try await Task.sleep(for: .milliseconds(500))
                    NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
                }
                return
            }
        }

        // Handle configuration validation errors with detailed feedback
        if case let KeyPathError.configuration(.validationFailed(errors)) = error {
            presentValidationFailureModal(errors)
            showStatusMessage(message: "❌ Configuration validation failed")
            return
        }

        // Handle configuration corruption with repair details
        if case let KeyPathError.configuration(.corruptedFormat(details)) = error {
            configCorruptionDetails = """
            Configuration corruption detected:

            \(details)

            KeyPath attempted automatic repair. If the repair was successful, your mapping has been saved with a corrected configuration.
            """
            configRepairSuccessful = false
            showingConfigCorruptionAlert = true
            showStatusMessage(message: "⚠️ Config repaired automatically")
            return
        }

        // Handle repair failures
        if case let KeyPathError.configuration(.repairFailed(reason)) = error {
            configCorruptionDetails = """
            Configuration repair failed:

            \(reason)

            A safe fallback configuration has been applied. Your system should continue working with basic functionality.
            """
            configRepairSuccessful = false
            showingConfigCorruptionAlert = true
            showStatusMessage(message: "❌ Config repair failed - using safe fallback")
            return
        }

        // Generic error handling for all other cases
        // Open wizard to help diagnose and fix the issue
        let errorDesc = error.localizedDescription
        showStatusMessage(message: "⚠️ \(errorDesc)")
        Task { @MainActor in
            try await Task.sleep(for: .seconds(1))
            NotificationCenter.default.post(name: .openInstallationWizard, object: nil)
        }
    }

    func presentValidationFailureModal(_ errors: [String]) {
        validationFailureErrors = errors
        validationFailureCopyText = errors.joined(separator: "\n")
        showingValidationFailureModal = true
    }

    func copyValidationErrorsToClipboard() {
        guard !validationFailureErrors.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let combined = validationFailureCopyText.isEmpty ? validationFailureErrors.joined(separator: "\n") : validationFailureCopyText
        pasteboard.setString(combined, forType: .string)
    }

    func openCurrentConfigInEditor() {
        kanataManager.openFileInZed(kanataManager.configPath)
    }

    func handleInputRecordTap() {
        if recordingCoordinator.isInputRecording() {
            recordingCoordinator.toggleInputRecording()
            return
        }

        guard kanataManager.isCompletelyInstalled() else {
            showingInstallAlert = true
            return
        }

        // Stop output recording if active before starting input
        if recordingCoordinator.isOutputRecording() {
            recordingCoordinator.toggleOutputRecording()
        }

        recordingCoordinator.toggleInputRecording()
    }

    func handleOutputRecordTap() {
        if recordingCoordinator.isOutputRecording() {
            recordingCoordinator.toggleOutputRecording()
            return
        }

        guard kanataManager.isCompletelyInstalled() else {
            showingInstallAlert = true
            return
        }

        // Stop input recording if active before starting output
        if recordingCoordinator.isInputRecording() {
            recordingCoordinator.toggleInputRecording()
        }

        recordingCoordinator.toggleOutputRecording()
    }

    func inputDisabledReason() -> String {
        var reasons: [String] = []
        if !kanataManager.isCompletelyInstalled(), !recordingCoordinator.isInputRecording() {
            reasons.append("notInstalled")
        }
        if NSApp?.isActive == false {
            reasons.append("appNotActive")
        }
        if NSApp?.keyWindow == nil {
            reasons.append("noKeyWindow")
        }
        return reasons.isEmpty ? "enabled" : reasons.joined(separator: "+")
    }

    func outputDisabledReason() -> String {
        var reasons: [String] = []
        if !kanataManager.isCompletelyInstalled(), !recordingCoordinator.isOutputRecording() {
            reasons.append("notInstalled")
        }
        if NSApp?.isActive == false {
            reasons.append("appNotActive")
        }
        if NSApp?.keyWindow == nil {
            reasons.append("noKeyWindow")
        }
        return reasons.isEmpty ? "enabled" : reasons.joined(separator: "+")
    }

    func logInputDisabledReason() {
        let reason = inputDisabledReason()
        if reason != lastInputDisabledReason {
            lastInputDisabledReason = reason
            AppLogger.shared.log("🧭 [UI] Input record button state: \(reason)")
        }
    }

    func logOutputDisabledReason() {
        let reason = outputDisabledReason()
        if reason != lastOutputDisabledReason {
            lastOutputDisabledReason = reason
            AppLogger.shared.log("🧭 [UI] Output record button state: \(reason)")
        }
    }
}
