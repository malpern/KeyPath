import AppKit
import Foundation
import KeyPathCore
import SwiftUI

@MainActor
protocol RecordingCapture: AnyObject {
    func setEventRouter(_ router: EventRouter?, kanataManager: RuntimeCoordinator?)
    func startSequenceCapture(mode: CaptureMode, callback: @escaping (KeySequence) -> Void)
    func stopCapture()
}

@MainActor
final class KeyboardCaptureAdapter: RecordingCapture {
    private let capture: KeyboardCapture

    init() {
        capture = KeyboardCapture()
    }

    func setEventRouter(_ router: EventRouter?, kanataManager: RuntimeCoordinator?) {
        capture.setEventRouter(router, kanataManager: kanataManager)
    }

    func startSequenceCapture(mode: CaptureMode, callback: @escaping (KeySequence) -> Void) {
        capture.startSequenceCapture(mode: mode, callback: callback)
    }

    func stopCapture() {
        capture.stopCapture()
    }
}

@MainActor
final class RecordingCoordinator: ObservableObject {
    struct ChannelState {
        var fieldText: String = ""
        var isRecording: Bool = false
        var capturedSequence: KeySequence?
        var buttonIcon: String = "play.circle.fill"
    }

    @Published private(set) var input = ChannelState()
    @Published private(set) var output = ChannelState()
    @Published var isSequenceMode: Bool {
        didSet {
            PreferencesService.shared.isSequenceMode = isSequenceMode
            inputPlaceholderRequested = true
            outputPlaceholderRequested = true
            refreshDisplayTexts()
        }
    }

    private var kanataManager: RuntimeCoordinator?
    private var showStatusMessage: ((String) -> Void)?
    private var permissionProvider: PermissionSnapshotProviding?
    private var keyboardCapture: RecordingCapture?
    private var captureFactory: () -> RecordingCapture = { KeyboardCaptureAdapter() }

    private var inputTimeoutTimer: Timer?
    private var outputTimeoutTimer: Timer?
    private var inputFinalizeTimer: Timer?
    private var outputFinalizeTimer: Timer?
    private var inputPlaceholderRequested = false
    private var outputPlaceholderRequested = false
    private var mappingsWereSuspended = false

    init() {
        // Initialize from saved preferences
        isSequenceMode = PreferencesService.shared.isSequenceMode
    }

    func configure(
        kanataManager: RuntimeCoordinator,
        statusHandler: @escaping (String) -> Void,
        permissionProvider: PermissionSnapshotProviding,
        keyboardCaptureFactory: @escaping () -> RecordingCapture = { KeyboardCaptureAdapter() }
    ) {
        self.kanataManager = kanataManager
        showStatusMessage = statusHandler
        self.permissionProvider = permissionProvider
        captureFactory = keyboardCaptureFactory
        refreshDisplayTexts()
    }

    // MARK: - Public API

    func toggleSequenceMode() {
        isSequenceMode.toggle()
    }

    func requestPlaceholders() {
        inputPlaceholderRequested = true
        outputPlaceholderRequested = true
        refreshDisplayTexts()
    }

    func toggleInputRecording() {
        if input.isRecording {
            stopInputRecording()
        } else {
            startInputRecording()
        }
    }

    func toggleOutputRecording() {
        if output.isRecording {
            stopOutputRecording()
        } else {
            startOutputRecording()
        }
    }

    func capturedInputSequence() -> KeySequence? {
        input.capturedSequence
    }

    func capturedOutputSequence() -> KeySequence? {
        output.capturedSequence
    }

    func clearCapturedSequences() {
        input.capturedSequence = nil
        output.capturedSequence = nil
        inputPlaceholderRequested = true
        outputPlaceholderRequested = true
        refreshDisplayTexts()
    }

    func inputDisplayText() -> String {
        input.fieldText
    }

    func outputDisplayText() -> String {
        output.fieldText
    }

    func inputButtonIcon() -> String {
        input.buttonIcon
    }

    func outputButtonIcon() -> String {
        output.buttonIcon
    }

    func isInputRecording() -> Bool {
        input.isRecording
    }

    func isOutputRecording() -> Bool {
        output.isRecording
    }

    func stopAllRecording() {
        stopInputRecording()
        stopOutputRecording()
        keyboardCapture?.stopCapture()
        keyboardCapture = nil
        if mappingsWereSuspended, let km = kanataManager {
            Task { _ = await km.resumeMappings() }
            mappingsWereSuspended = false
            AppLogger.shared.log("🎛️ [Coordinator] Resumed mappings after stopAllRecording()")
        }
    }

    func saveMapping(
        kanataManager: RuntimeCoordinator,
        onSuccess: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        guard let rawInput = capturedInputSequence(),
              let rawOutput = capturedOutputSequence()
        else {
            AppLogger.shared.log("❌ [Coordinator] Save requested without both sequences")
            await MainActor.run {
                onError(
                    KeyPathError.coordination(.recordingFailed(reason: "Missing input/output sequences"))
                )
            }
            return
        }

        // Normalize to remove accidental duplicates (e.g., from multiple listeners)
        let inputSequence = normalize(rawInput)
        let outputSequence = normalize(rawOutput)

        AppLogger.shared.log("📝 [RecordingCoordinator] saveMapping called:")
        AppLogger.shared.log("  - Input keys: \(inputSequence.keys.count), modifiers: \(inputSequence.keys.first?.modifiers ?? [])")
        AppLogger.shared.log("  - Output keys: \(outputSequence.keys.count), modifiers: \(outputSequence.keys.map(\.modifiers))")

        // Simple path: single key → single key (no modifiers) => literal mapping via ConfigurationService
        if inputSequence.keys.count == 1,
           outputSequence.keys.count == 1,
           inputSequence.keys[0].modifiers.isEmpty,
           outputSequence.keys[0].modifiers.isEmpty {
            let inKey = inputSequence.keys[0].baseKey
            let outKey = outputSequence.keys[0].baseKey
            AppLogger.shared.log("📝 [RecordingCoordinator] Using SIMPLE path: \(inKey) → \(outKey)")
            do {
                try await kanataManager.saveConfiguration(input: inKey, output: outKey)
                await kanataManager.updateStatus()
                await MainActor.run {
                    onSuccess("Key mapping saved: \(inKey) → \(outKey)")
                    clearCapturedSequences()
                }
            } catch {
                AppLogger.shared.log("❌ [Coordinator] Error saving simple mapping: \(error)")
                onError(error)
            }
            return
        }

        // Otherwise, generate a full config (macros/sequences/chords)
        AppLogger.shared.log("📝 [RecordingCoordinator] Using COMPLEX path (multi-key or modifiers)")
        let configGenerator = KanataConfigGenerator(kanataManager: kanataManager)
        do {
            let generatedConfig = try await configGenerator.generateMapping(
                input: inputSequence, output: outputSequence
            )
            try await kanataManager.saveGeneratedConfiguration(generatedConfig)
            AppLogger.shared.log("📝 [RecordingCoordinator] Generated config saved successfully")

            // Also create a CustomRule so it appears in the Custom Rules UI
            let inputKanata = convertSequenceToKanataInput(inputSequence)
            let outputKanata = convertSequenceToKanataOutput(outputSequence)
            AppLogger.shared.log("📝 [RecordingCoordinator] Creating CustomRule: '\(inputKanata)' → '\(outputKanata)'")
            let customRule = CustomRule(
                input: inputKanata,
                output: outputKanata,
                isEnabled: true,
                notes: "Created via recording"
            )
            let saveResult = await kanataManager.saveCustomRule(customRule, skipReload: true)
            AppLogger.shared.log("📝 [RecordingCoordinator] CustomRule save result: \(saveResult)")

            await kanataManager.updateStatus()

            await MainActor.run {
                onSuccess(
                    "Key mapping saved: \(inputSequence.displayString) → \(outputSequence.displayString)"
                )
                clearCapturedSequences()
            }
        } catch {
            AppLogger.shared.log("❌ [Coordinator] Error saving mapping: \(error)")
            onError(error)
        }
    }

    // MARK: - Kanata Key Conversion

    /// Convert KeySequence to Kanata input key format
    private func convertSequenceToKanataInput(_ sequence: KeySequence) -> String {
        guard let firstKey = sequence.keys.first else { return "spc" }

        var result = firstKey.baseKey.lowercased()

        // Handle special key names
        let keyMap: [String: String] = [
            "space": "spc",
            "return": "ret",
            "enter": "ret",
            "escape": "esc",
            "backspace": "bspc",
            "delete": "del",
            "caps": "caps",
            "capslock": "caps"
        ]

        if let mapped = keyMap[result] {
            result = mapped
        }

        // Add modifiers if present
        if !firstKey.modifiers.isEmpty {
            var modifierStr = ""
            if firstKey.modifiers.contains(.control) { modifierStr += "C-" }
            if firstKey.modifiers.contains(.option) { modifierStr += "A-" }
            if firstKey.modifiers.contains(.shift) { modifierStr += "S-" }
            if firstKey.modifiers.contains(.command) { modifierStr += "M-" }
            result = modifierStr + result
        }

        return result
    }

    /// Convert KeySequence to Kanata output format (may include multiple keys)
    private func convertSequenceToKanataOutput(_ sequence: KeySequence) -> String {
        let keyStrings = sequence.keys.map { keyPress -> String in
            var result = keyPress.baseKey.lowercased()

            // Handle special key names
            let keyMap: [String: String] = [
                "space": "spc",
                "return": "ret",
                "enter": "ret",
                "escape": "esc",
                "backspace": "bspc",
                "delete": "del"
            ]

            if let mapped = keyMap[result] {
                result = mapped
            }

            // Add modifiers
            if keyPress.modifiers.contains(.control) { result = "C-" + result }
            if keyPress.modifiers.contains(.option) { result = "A-" + result }
            if keyPress.modifiers.contains(.shift) { result = "S-" + result }
            if keyPress.modifiers.contains(.command) { result = "M-" + result }

            return result
        }

        return keyStrings.joined(separator: " ")
    }

    // MARK: - Internal Helpers

    private func startInputRecording() {
        guard !input.isRecording else { return }
        AppLogger.shared.log("🚩 [Coordinator] startInputRecording()")
        inputTimeoutTimer?.invalidate()
        input.isRecording = true
        input.capturedSequence = nil
        refreshDisplayTexts()

        guard let permissionProvider else {
            failInputRecording(with: "permissionFailure")
            return
        }

        Task {
            let snapshot = await permissionProvider.currentSnapshot()

            guard snapshot.keyPath.accessibility.isReady else {
                await MainActor.run {
                    self.failInputRecording(with: "permissionFailure")
                }
                return
            }

            await MainActor.run {
                self.prepareKeyboardCaptureIfNeeded()
                guard let capture = self.keyboardCapture else {
                    self.failInputRecording(with: "captureInitializationFailure")
                    return
                }

                // Check if we should suspend mappings for raw key capture
                if !PreferencesService.shared.applyMappingsDuringRecording,
                   let km = self.kanataManager {
                    Task {
                        let wasPaused = await km.pauseMappings()
                        await MainActor.run {
                            self.mappingsWereSuspended = wasPaused
                            if wasPaused {
                                AppLogger.shared.log("🎛️ [Coordinator] Paused mappings for raw key capture (input)")
                            }
                        }
                    }
                }

                self.logFocusState(prefix: "[Coordinator:Input]")
                capture.setEventRouter(nil, kanataManager: self.kanataManager)
                let mode: CaptureMode = self.isSequenceMode ? .sequence : .chord

                self.inputTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) {
                    [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if self.input.isRecording {
                            self.failInputRecording(with: "timeout")
                            self.keyboardCapture?.stopCapture()
                        }
                    }
                }

                capture.startSequenceCapture(mode: mode) { keySequence in
                    Task { @MainActor in
                        // Provisional streaming update
                        self.inputTimeoutTimer?.invalidate()
                        self.input.capturedSequence = keySequence
                        self.refreshDisplayTexts()

                        // Schedule finalize timer based on mode
                        self.inputFinalizeTimer?.invalidate()
                        let finalizeDelay: TimeInterval = self.finalizeDelayDuration(for: mode)
                        self.inputFinalizeTimer = Timer.scheduledTimer(
                            withTimeInterval: finalizeDelay, repeats: false
                        ) { [weak self] _ in
                            Task { @MainActor in
                                guard let self else { return }
                                if self.input.isRecording {
                                    self.input.isRecording = false
                                    self.refreshDisplayTexts()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func finalizeDelayDuration(for mode: CaptureMode) -> TimeInterval {
        switch mode {
        case .sequence:
            TestEnvironment.isTestMode ? 0.2 : 2.1
        case .chord, .single:
            0.08
        }
    }

    private func failInputRecording(with reason: String) {
        inputTimeoutTimer?.invalidate()
        input.isRecording = false
        input.capturedSequence = nil
        let displayInfo = recordingFailureDisplayInfo(for: reason)
        input.fieldText = displayInfo.displayMessage
        updateButtonIcon(&input)
        if displayInfo.shouldShowBanner {
            showStatusMessage?(displayInfo.bannerMessage)
        }

        // Resume mappings if we suspended them
        if mappingsWereSuspended, let km = kanataManager {
            Task {
                _ = await km.resumeMappings()
                await MainActor.run {
                    self.mappingsWereSuspended = false
                    AppLogger.shared.log("🎛️ [Coordinator] Resumed mappings after input recording failure")
                }
            }
        }
    }

    private func stopInputRecording() {
        guard input.isRecording else { return }
        inputTimeoutTimer?.invalidate()
        input.isRecording = false
        refreshDisplayTexts()
        keyboardCapture?.stopCapture()

        // Resume mappings if we suspended them
        if mappingsWereSuspended, let km = kanataManager {
            Task {
                _ = await km.resumeMappings()
                await MainActor.run {
                    self.mappingsWereSuspended = false
                    AppLogger.shared.log("🎛️ [Coordinator] Resumed mappings after input recording")
                }
            }
        }
    }

    private func startOutputRecording() {
        guard !output.isRecording else { return }
        AppLogger.shared.log("🚩 [Coordinator] startOutputRecording()")
        outputTimeoutTimer?.invalidate()
        output.isRecording = true
        output.capturedSequence = nil
        refreshDisplayTexts()

        guard let permissionProvider else {
            failOutputRecording(with: "permissionFailure")
            return
        }

        Task {
            let snapshot = await permissionProvider.currentSnapshot()

            guard snapshot.keyPath.accessibility.isReady else {
                await MainActor.run {
                    self.failOutputRecording(with: "permissionFailure")
                }
                return
            }

            await MainActor.run {
                self.prepareKeyboardCaptureIfNeeded()
                guard let capture = self.keyboardCapture else {
                    self.failOutputRecording(with: "captureInitializationFailure")
                    return
                }

                // Check if we should suspend mappings for raw key capture
                if !PreferencesService.shared.applyMappingsDuringRecording,
                   let km = self.kanataManager {
                    Task {
                        let wasPaused = await km.pauseMappings()
                        await MainActor.run {
                            self.mappingsWereSuspended = wasPaused
                            if wasPaused {
                                AppLogger.shared.log("🎛️ [Coordinator] Paused mappings for raw key capture (output)")
                            }
                        }
                    }
                }

                self.logFocusState(prefix: "[Coordinator:Output]")
                capture.setEventRouter(nil, kanataManager: self.kanataManager)
                let mode: CaptureMode = self.isSequenceMode ? .sequence : .chord

                self.outputTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) {
                    [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if self.output.isRecording {
                            self.failOutputRecording(with: "timeout")
                            self.keyboardCapture?.stopCapture()
                        }
                    }
                }

                capture.startSequenceCapture(mode: mode) { keySequence in
                    Task { @MainActor in
                        // Provisional streaming update
                        self.outputTimeoutTimer?.invalidate()
                        self.output.capturedSequence = keySequence
                        self.refreshDisplayTexts()

                        // Schedule finalize timer based on mode
                        self.outputFinalizeTimer?.invalidate()
                        let finalizeDelay: TimeInterval = (mode == .sequence) ? 2.1 : 0.08
                        self.outputFinalizeTimer = Timer.scheduledTimer(
                            withTimeInterval: finalizeDelay, repeats: false
                        ) { [weak self] _ in
                            Task { @MainActor in
                                guard let self else { return }
                                if self.output.isRecording {
                                    self.output.isRecording = false
                                    self.refreshDisplayTexts()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func failOutputRecording(with reason: String) {
        outputTimeoutTimer?.invalidate()
        output.isRecording = false
        output.capturedSequence = nil
        let displayInfo = recordingFailureDisplayInfo(for: reason)
        output.fieldText = displayInfo.displayMessage
        updateButtonIcon(&output)
        if displayInfo.shouldShowBanner {
            showStatusMessage?(displayInfo.bannerMessage)
        }

        // Resume mappings if we suspended them
        if mappingsWereSuspended, let km = kanataManager {
            Task {
                _ = await km.resumeMappings()
                await MainActor.run {
                    self.mappingsWereSuspended = false
                    AppLogger.shared.log("🎛️ [Coordinator] Resumed mappings after output recording failure")
                }
            }
        }
    }

    private func stopOutputRecording() {
        guard output.isRecording else { return }
        outputTimeoutTimer?.invalidate()
        output.isRecording = false
        refreshDisplayTexts()
        keyboardCapture?.stopCapture()

        // Resume mappings if we suspended them
        if mappingsWereSuspended, let km = kanataManager {
            Task {
                _ = await km.resumeMappings()
                await MainActor.run {
                    self.mappingsWereSuspended = false
                    AppLogger.shared.log("🎛️ [Coordinator] Resumed mappings after output recording")
                }
            }
        }
    }

    private func prepareKeyboardCaptureIfNeeded() {
        if keyboardCapture == nil {
            keyboardCapture = captureFactory()
        }
    }

    private func refreshDisplayTexts() {
        refreshInputDisplayText()
        refreshOutputDisplayText()
    }

    private func refreshInputDisplayText() {
        if let sequence = input.capturedSequence {
            input.fieldText = sequence.displayString
        } else if input.isRecording {
            input.fieldText = recordingPromptText()
        } else {
            // Empty when idle - placeholder only shows during recording
            input.fieldText = ""
        }
        updateButtonIcon(&input)
    }

    private func refreshOutputDisplayText() {
        if let sequence = output.capturedSequence {
            output.fieldText = sequence.displayString
        } else if output.isRecording {
            output.fieldText = recordingPromptText()
        } else {
            // Empty when idle - placeholder only shows during recording
            output.fieldText = ""
        }
        updateButtonIcon(&output)
    }

    private func idlePlaceholderText() -> String {
        isSequenceMode ? "Press key sequence..." : "Press key combination..."
    }

    private func recordingPromptText() -> String {
        // Simple prompt without raw/effective indicators
        idlePlaceholderText()
    }

    private func updateButtonIcon(_ channel: inout ChannelState) {
        if channel.isRecording {
            channel.buttonIcon = "xmark.circle.fill"
        } else if channel.capturedSequence == nil || channel.fieldText.isEmpty {
            channel.buttonIcon = "play.circle.fill"
        } else {
            channel.buttonIcon = "arrow.clockwise.circle.fill"
        }
    }

    private func logFocusState(prefix: String) {
        guard let app = NSApp else {
            AppLogger.shared.log("🔍 \(prefix) Focus: NSApp unavailable (likely running in tests)")
            return
        }

        let isActive = app.isActive
        let keyWindow = app.keyWindow != nil
        let occlusion = app.keyWindow?.occlusionState.rawValue ?? 0
        AppLogger.shared.log(
            "🔍 \(prefix) Focus: appActive=\(isActive), keyWindow=\(keyWindow), occlusion=\(occlusion)"
        )
    }
}

// MARK: - Normalization Helpers

private extension RecordingCoordinator {
    func normalize(_ sequence: KeySequence) -> KeySequence {
        guard !sequence.keys.isEmpty else { return sequence }
        let window: TimeInterval = 0.06
        var result: [KeyPress] = []
        for kp in sequence.keys.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let last = result.last,
               last.baseKey == kp.baseKey,
               last.modifiers == kp.modifiers,
               kp.timestamp.timeIntervalSince(last.timestamp) <= window {
                continue
            }
            result.append(kp)
        }
        let mode: CaptureMode = (result.count <= 1) ? .single : sequence.captureMode
        return KeySequence(keys: result, captureMode: mode, timestamp: sequence.timestamp)
    }
}

extension RecordingCoordinator {
    /// Recording coordinator errors
    /// Helper to get display information for recording failure reasons
    private struct RecordingFailureDisplayInfo {
        let displayMessage: String
        let bannerMessage: String
        let shouldShowBanner: Bool
    }

    private func recordingFailureDisplayInfo(for reason: String) -> RecordingFailureDisplayInfo {
        switch reason {
        case "permissionFailure":
            RecordingFailureDisplayInfo(
                displayMessage: "⚠️ Accessibility permission required for recording",
                bannerMessage:
                "❌ Recording requires Accessibility permission. Open the Installation Wizard to grant access.",
                shouldShowBanner: true
            )
        case "captureInitializationFailure":
            RecordingFailureDisplayInfo(
                displayMessage: "⚠️ Failed to initialize keyboard capture",
                bannerMessage: "❌ Failed to start keyboard capture. Check KeyPath diagnostics.",
                shouldShowBanner: true
            )
        case "timeout":
            RecordingFailureDisplayInfo(
                displayMessage: "⚠️ Recording timed out - try again",
                bannerMessage: "⚠️ Recording timed out — try again.",
                shouldShowBanner: true
            )
        default:
            RecordingFailureDisplayInfo(
                displayMessage: "⚠️ Recording failed",
                bannerMessage: "❌ Recording failed: \(reason)",
                shouldShowBanner: true
            )
        }
    }
}
