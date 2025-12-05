import AppKit
import Foundation
import KeyPathCore
import SwiftUI

// MARK: - Mapper View Model Types

/// Info about a selected app for launch action
struct AppLaunchInfo: Equatable {
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage

    /// The kanata output string for this app launch
    var kanataOutput: String {
        // Use bundle identifier if available, otherwise app name
        let appId = bundleIdentifier ?? name
        return "(push-msg \"launch:\(appId)\")"
    }
}

/// Info about a selected system action or media key
struct SystemActionInfo: Equatable, Identifiable {
    let id: String // The action identifier (e.g., "dnd", "spotlight", "pp" for play/pause)
    let name: String // Human-readable name
    let sfSymbol: String // SF Symbol icon name
    /// If non-nil, this is a direct keycode output (e.g., "pp", "prev", "next")
    /// If nil, this is a push-msg system action
    let kanataKeycode: String?
    /// Canonical name returned by kanata simulator (e.g., "MediaTrackPrevious", "MediaPlayPause")
    let simulatorName: String?

    init(id: String, name: String, sfSymbol: String, kanataKeycode: String? = nil, simulatorName: String? = nil) {
        self.id = id
        self.name = name
        self.sfSymbol = sfSymbol
        self.kanataKeycode = kanataKeycode
        self.simulatorName = simulatorName
    }

    /// The kanata output string for this action
    var kanataOutput: String {
        if let keycode = kanataKeycode {
            return keycode
        }
        return "(push-msg \"system:\(id)\")"
    }

    /// Whether this is a media key (direct keycode) vs push-msg action
    var isMediaKey: Bool {
        kanataKeycode != nil
    }

    /// All available system actions and media keys
    /// SF Symbols match macOS function key icons (non-filled variants)
    static let allActions: [SystemActionInfo] = [
        // Push-msg system actions
        SystemActionInfo(id: "spotlight", name: "Spotlight", sfSymbol: "magnifyingglass"),
        SystemActionInfo(id: "mission-control", name: "Mission Control", sfSymbol: "rectangle.3.group"),
        SystemActionInfo(id: "launchpad", name: "Launchpad", sfSymbol: "square.grid.3x3"),
        SystemActionInfo(id: "dnd", name: "Do Not Disturb", sfSymbol: "moon"),
        SystemActionInfo(id: "notification-center", name: "Notification Center", sfSymbol: "bell"),
        SystemActionInfo(id: "dictation", name: "Dictation", sfSymbol: "mic"),
        SystemActionInfo(id: "siri", name: "Siri", sfSymbol: "waveform.circle"),
        // Media keys (direct keycodes)
        // simulatorName is the canonical name returned by kanata simulator (from keyberon KeyCode enum)
        SystemActionInfo(id: "play-pause", name: "Play/Pause", sfSymbol: "playpause", kanataKeycode: "pp", simulatorName: "MediaPlayPause"),
        SystemActionInfo(id: "next-track", name: "Next Track", sfSymbol: "forward", kanataKeycode: "next", simulatorName: "MediaNextSong"),
        SystemActionInfo(id: "prev-track", name: "Previous Track", sfSymbol: "backward", kanataKeycode: "prev", simulatorName: "MediaPreviousSong"),
        SystemActionInfo(id: "mute", name: "Mute", sfSymbol: "speaker.slash", kanataKeycode: "mute", simulatorName: "Mute"),
        SystemActionInfo(id: "volume-up", name: "Volume Up", sfSymbol: "speaker.wave.3", kanataKeycode: "volu", simulatorName: "VolUp"),
        SystemActionInfo(id: "volume-down", name: "Volume Down", sfSymbol: "speaker.wave.1", kanataKeycode: "voldwn", simulatorName: "VolDown"),
        SystemActionInfo(id: "brightness-up", name: "Brightness Up", sfSymbol: "sun.max", kanataKeycode: "brup", simulatorName: "BrightnessUp"),
        SystemActionInfo(id: "brightness-down", name: "Brightness Down", sfSymbol: "sun.min", kanataKeycode: "brdown", simulatorName: "BrightnessDown")
    ]

    /// Look up a SystemActionInfo by its kanata output (keycode, display name, or simulator name)
    static func find(byOutput output: String) -> SystemActionInfo? {
        // Check by name first (for display labels from overlay)
        if let action = allActions.first(where: { $0.name == output }) {
            return action
        }
        // Check by kanata keycode (for direct key outputs like "pp", "next")
        if let action = allActions.first(where: { $0.kanataKeycode == output }) {
            return action
        }
        // Check by simulator canonical name (e.g., "MediaTrackPrevious", "MediaPlayPause")
        if let action = allActions.first(where: { $0.simulatorName == output }) {
            return action
        }
        return nil
    }
}

@MainActor
class MapperViewModel: ObservableObject {
    @Published var inputLabel: String = "a"
    @Published var outputLabel: String = "a"
    @Published var isRecordingInput = false
    @Published var isRecordingOutput = false
    @Published var isSaving = false
    @Published var statusMessage: String?
    @Published var statusIsError = false
    @Published var currentLayer: String = "base"
    /// Selected app for launch action (nil = normal key output)
    @Published var selectedApp: AppLaunchInfo?
    /// Selected system action (nil = normal key output)
    @Published var selectedSystemAction: SystemActionInfo?
    /// Key code of the captured input (for overlay-style rendering)
    @Published var inputKeyCode: UInt16?

    private var inputSequence: KeySequence?
    private var outputSequence: KeySequence?
    private var keyboardCapture: KeyboardCapture?
    private var kanataManager: RuntimeCoordinator?
    private var finalizeTimer: Timer?
    /// ID of the last saved custom rule (for clearing/deleting)
    private var lastSavedRuleID: UUID?
    /// Original key context from overlay click (for reset after clear)
    var originalInputKey: String?
    private var originalOutputKey: String?
    /// Original layer from overlay click
    private var originalLayer: String?

    /// State saved before starting output recording (for restore on cancel)
    private var savedOutputLabel: String?
    private var savedOutputSequence: KeySequence?
    private var savedSelectedApp: AppLaunchInfo?
    private var savedSelectedSystemAction: SystemActionInfo?

    /// Delay before finalizing a sequence capture (allows for multi-key sequences)
    private let sequenceFinalizeDelay: TimeInterval = 0.8

    var canSave: Bool {
        inputSequence != nil && (outputSequence != nil || selectedApp != nil || selectedSystemAction != nil)
    }

    func configure(kanataManager: RuntimeCoordinator) {
        self.kanataManager = kanataManager
    }

    /// Set the current layer
    func setLayer(_ layer: String) {
        currentLayer = layer
        AppLogger.shared.log("🗂️ [MapperViewModel] Layer set to: \(layer)")
    }

    /// Apply preset values from overlay click
    func applyPresets(input: String, output: String, layer: String? = nil) {
        // Stop any active recording
        stopRecording()

        // Store original context for reset after clear
        originalInputKey = input
        originalOutputKey = output
        originalLayer = layer

        // Clear any previously saved rule ID since we're starting fresh
        lastSavedRuleID = nil
        selectedApp = nil
        selectedSystemAction = nil

        // Set the layer
        if let layer {
            currentLayer = layer
        }

        // Set the input label and sequence
        inputLabel = formatKeyForDisplay(input)
        inputSequence = KeySequence(
            keys: [KeyPress(baseKey: input, modifiers: [], keyCode: 0)],
            captureMode: .single
        )

        // Check if output is a system action or media key
        if let systemAction = SystemActionInfo.find(byOutput: output) {
            // It's a system action/media key - set selectedSystemAction for SF Symbol rendering
            selectedSystemAction = systemAction
            outputLabel = systemAction.name
            outputSequence = nil
            AppLogger.shared.log("🗺️ [MapperViewModel] Preset output is system action: \(systemAction.name)")
        } else {
            // Regular key mapping
            outputLabel = formatKeyForDisplay(output)
            outputSequence = KeySequence(
                keys: [KeyPress(baseKey: output, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
        }

        statusMessage = nil
        statusIsError = false

        AppLogger.shared.log("📝 [MapperViewModel] Applied presets: \(input) → \(output) [layer: \(currentLayer)]")
    }

    /// Format a kanata key name for display (e.g., "leftmeta" -> "⌘")
    private func formatKeyForDisplay(_ key: String) -> String {
        let displayMap: [String: String] = [
            "leftmeta": "⌘",
            "rightmeta": "⌘",
            "leftalt": "⌥",
            "rightalt": "⌥",
            "leftshift": "⇧",
            "rightshift": "⇧",
            "leftctrl": "⌃",
            "rightctrl": "⌃",
            "capslock": "⇪",
            "space": "␣",
            "enter": "↩",
            "tab": "⇥",
            "backspace": "⌫",
            "esc": "⎋",
            "left": "←",
            "right": "→",
            "up": "↑",
            "down": "↓"
        ]
        return displayMap[key.lowercased()] ?? key.uppercased()
    }

    func toggleInputRecording() {
        if isRecordingInput {
            stopRecording()
        } else {
            // Stop output recording if active
            if isRecordingOutput {
                stopRecording()
            }
            startInputRecording()
        }
    }

    func toggleOutputRecording() {
        if isRecordingOutput {
            stopRecording()
        } else {
            // Stop input recording if active
            if isRecordingInput {
                stopRecording()
            }
            startOutputRecording()
        }
    }

    private func startInputRecording() {
        isRecordingInput = true
        inputSequence = nil
        inputKeyCode = nil
        inputLabel = "..."
        statusMessage = "Press keys (sequence supported)"
        statusIsError = false
        startCapture(isInput: true)
    }

    private func startOutputRecording() {
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
        startCapture(isInput: false)
    }

    private func startCapture(isInput: Bool) {
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

            Task { @MainActor in
                // Update the captured sequence (streaming updates)
                if isInput {
                    self.inputSequence = sequence
                    self.inputLabel = sequence.displayString
                    // Store first key's keyCode for overlay-style rendering
                    if let firstKey = sequence.keys.first {
                        let keyCode = UInt16(firstKey.keyCode)
                        self.inputKeyCode = keyCode

                        // Look up current mapping for this key and update output
                        self.lookupAndSetOutput(forKeyCode: keyCode)
                    }
                } else {
                    self.outputSequence = sequence
                    self.outputLabel = sequence.displayString
                }

                // Reset finalize timer - wait for more keys
                self.finalizeTimer?.invalidate()
                self.finalizeTimer = Timer.scheduledTimer(
                    withTimeInterval: self.sequenceFinalizeDelay,
                    repeats: false
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.finalizeCapture()
                    }
                }
            }
        }
    }

    /// Look up the current output for a key code from the overlay's layer map
    private func lookupAndSetOutput(forKeyCode keyCode: UInt16) {
        // Clear any selected app/system action since we're switching keys
        selectedApp = nil
        selectedSystemAction = nil

        // Look up the current mapping from the overlay controller
        if let mapping = LiveKeyboardOverlayController.shared.lookupCurrentMapping(forKeyCode: keyCode) {
            // Check if this is a system action or media key
            if let systemAction = SystemActionInfo.find(byOutput: mapping.output) {
                // It's a system action/media key - set selectedSystemAction for SF Symbol rendering
                selectedSystemAction = systemAction
                outputLabel = systemAction.name
                outputSequence = nil
                AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) is system action: \(systemAction.name)")
            } else {
                // Regular key mapping
                outputLabel = formatKeyForDisplay(mapping.output)
                outputSequence = KeySequence(
                    keys: [KeyPress(baseKey: mapping.output, modifiers: [], keyCode: 0)],
                    captureMode: .single
                )
            }

            // Store original context for reset
            originalInputKey = mapping.inputKey
            originalOutputKey = mapping.output
            originalLayer = LiveKeyboardOverlayController.shared.currentLayerName
            currentLayer = originalLayer ?? "base"

            AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) maps to: \(mapping.output) in layer \(currentLayer)")
        } else {
            // No mapping found - default to key maps to itself
            let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)
            outputLabel = formatKeyForDisplay(inputKey)
            outputSequence = KeySequence(
                keys: [KeyPress(baseKey: inputKey, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
            originalInputKey = inputKey
            originalOutputKey = inputKey
        }
    }

    private func finalizeCapture() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil

        // Stop recording but keep the captured sequence
        keyboardCapture?.stopCapture()
        isRecordingInput = false
        isRecordingOutput = false
        statusMessage = nil

        AppLogger.shared.log("🎯 [MapperViewModel] finalizeCapture: canSave=\(canSave) selectedApp=\(selectedApp?.name ?? "nil") inputSeq=\(inputSequence?.displayString ?? "nil")")

        // Auto-save when input is captured and we have either output or app
        if canSave, let manager = kanataManager {
            Task {
                if selectedApp != nil {
                    // App launch mapping
                    AppLogger.shared.log("🎯 [MapperViewModel] Calling saveAppLaunchMapping")
                    await saveAppLaunchMapping(kanataManager: manager)
                } else {
                    // Key-to-key mapping
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
        isRecordingInput = false
        isRecordingOutput = false

        // If we stopped without capturing anything, restore previous state
        if inputSequence == nil {
            inputLabel = "a"
            inputKeyCode = nil
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
                // No saved state, default to "a"
                outputLabel = "a"
            }
        }

        // Clear saved state
        savedOutputLabel = nil
        savedOutputSequence = nil
        savedSelectedApp = nil
        savedSelectedSystemAction = nil

        statusMessage = nil
    }

    func stopKeyCapture() {
        stopRecording()
        keyboardCapture = nil
    }

    func save(kanataManager: RuntimeCoordinator) async {
        guard let inputSeq = inputSequence,
              let outputSeq = outputSequence,
              !inputSeq.isEmpty,
              !outputSeq.isEmpty
        else {
            statusMessage = "Capture both input and output first"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        do {
            // Use the existing config generator for complex sequences
            let configGenerator = KanataConfigGenerator(kanataManager: kanataManager)
            let generatedConfig = try await configGenerator.generateMapping(
                input: inputSeq,
                output: outputSeq
            )
            try await kanataManager.saveGeneratedConfiguration(generatedConfig)

            // Also save as custom rule for UI visibility
            let inputKanata = convertSequenceToKanataFormat(inputSeq)
            let outputKanata = convertSequenceToKanataFormat(outputSeq)

            // Convert currentLayer string to RuleCollectionLayer
            let targetLayer = layerFromString(currentLayer)

            // Use makeCustomRule to reuse existing rule ID for the same input key
            // This prevents duplicate keys in defsrc which causes Kanata validation errors
            var customRule = kanataManager.makeCustomRule(input: inputKanata, output: outputKanata)
            customRule.notes = "Created via Mapper [\(currentLayer) layer]"
            customRule.targetLayer = targetLayer

            _ = await kanataManager.saveCustomRule(customRule, skipReload: true)

            // Track the saved rule ID for potential clearing
            lastSavedRuleID = customRule.id

            // Notify overlay to refresh with new mapping
            NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)

            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved mapping: \(inputSeq.displayString) → \(outputSeq.displayString) [layer: \(currentLayer)] (ruleID: \(customRule.id))")
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] Save failed: \(error)")
        }

        isSaving = false
    }

    private func reset() {
        inputLabel = "a"
        outputLabel = "a"
        inputSequence = nil
        outputSequence = nil
        inputKeyCode = nil
        selectedApp = nil
        selectedSystemAction = nil
        statusMessage = nil
    }

    /// Clear all values, delete the saved rule, and reset to original key context (or default)
    func clear() {
        stopRecording()
        selectedApp = nil
        selectedSystemAction = nil

        // Delete the saved rule if we have one
        if let ruleID = lastSavedRuleID, let manager = kanataManager {
            Task {
                await manager.removeCustomRule(withID: ruleID)
                // Notify overlay to refresh
                NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
                AppLogger.shared.log("🧹 [MapperViewModel] Deleted rule \(ruleID) and refreshed overlay")
            }
            lastSavedRuleID = nil
        }

        // Reset to original key context if opened from overlay, otherwise default
        if let origInput = originalInputKey, let origOutput = originalOutputKey {
            // Re-apply the original presets
            inputLabel = formatKeyForDisplay(origInput)
            inputSequence = KeySequence(
                keys: [KeyPress(baseKey: origInput, modifiers: [], keyCode: 0)],
                captureMode: .single
            )

            // Check if original output is a system action or media key
            if let systemAction = SystemActionInfo.find(byOutput: origOutput) {
                selectedSystemAction = systemAction
                outputLabel = systemAction.name
                outputSequence = nil
            } else {
                outputLabel = formatKeyForDisplay(origOutput)
                outputSequence = KeySequence(
                    keys: [KeyPress(baseKey: origOutput, modifiers: [], keyCode: 0)],
                    captureMode: .single
                )
            }

            statusMessage = nil
            AppLogger.shared.log("🧹 [MapperViewModel] Reset to original key: \(origInput) → \(origOutput)")
        } else {
            // No context - reset to default
            reset()
            AppLogger.shared.log("🧹 [MapperViewModel] Cleared mapping (no key context)")
        }
    }

    /// Reset entire keyboard to default mappings (clears all custom rules and collections)
    func resetAllToDefaults(kanataManager: RuntimeCoordinator) async {
        stopRecording()

        do {
            try await kanataManager.resetToDefaultConfig()

            // Reset local state
            reset()
            lastSavedRuleID = nil
            originalInputKey = nil
            originalOutputKey = nil
            originalLayer = nil
            currentLayer = "base"

            // Notify overlay to refresh
            NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)

            statusMessage = "✓ Reset to defaults"
            statusIsError = false
            AppLogger.shared.log("🔄 [MapperViewModel] Reset entire keyboard to defaults")
        } catch {
            statusMessage = "Reset failed: \(error.localizedDescription)"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] Reset all failed: \(error)")
        }
    }

    /// Open file picker to select an app for launch action
    func pickAppForOutput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Select an application to launch"
        panel.prompt = "Select"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                self?.handleSelectedApp(at: url)
            }
        }
    }

    /// Process the selected app and update output
    private func handleSelectedApp(at url: URL) {
        let appName = url.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier

        // Get the app icon
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64) // Reasonable size for display

        let appInfo = AppLaunchInfo(
            name: appName,
            bundleIdentifier: bundleIdentifier,
            icon: icon
        )

        selectedApp = appInfo
        selectedSystemAction = nil // Clear any system action selection
        outputLabel = appName
        outputSequence = nil // Clear any key sequence output

        AppLogger.shared.log("📱 [MapperViewModel] Selected app: \(appName) (\(bundleIdentifier ?? "no bundle ID"))")
        AppLogger.shared.log("📱 [MapperViewModel] kanataOutput will be: \(appInfo.kanataOutput)")

        // Auto-save if input is already set
        if let manager = kanataManager, inputSequence != nil {
            AppLogger.shared.log("📱 [MapperViewModel] Input already set, auto-saving...")
            Task {
                await saveAppLaunchMapping(kanataManager: manager)
            }
        } else {
            AppLogger.shared.log("📱 [MapperViewModel] Waiting for input to be recorded (inputSequence=\(inputSequence?.displayString ?? "nil"), manager=\(kanataManager != nil ? "set" : "nil"))")
        }
    }

    /// Save a mapping that launches an app
    private func saveAppLaunchMapping(kanataManager: RuntimeCoordinator) async {
        AppLogger.shared.log("🚀 [MapperViewModel] saveAppLaunchMapping called")

        guard let inputSeq = inputSequence, let app = selectedApp else {
            AppLogger.shared.log("⚠️ [MapperViewModel] saveAppLaunchMapping: missing input or app")
            statusMessage = "Set input key first"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        let inputKanata = convertSequenceToKanataFormat(inputSeq)
        let targetLayer = layerFromString(currentLayer)

        AppLogger.shared.log("🚀 [MapperViewModel] Creating rule: input='\(inputKanata)' output='\(app.kanataOutput)' layer=\(targetLayer)")

        // Use makeCustomRule to reuse existing rule ID for the same input key
        // This prevents duplicate keys in defsrc which causes Kanata validation errors
        var customRule = kanataManager.makeCustomRule(input: inputKanata, output: app.kanataOutput)
        customRule.notes = "Launch \(app.name) [\(currentLayer) layer]"
        customRule.targetLayer = targetLayer

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        AppLogger.shared.log("🚀 [MapperViewModel] saveCustomRule returned: \(success)")

        if success {
            lastSavedRuleID = customRule.id
            // Notify overlay to refresh
            NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved app launch: \(inputSeq.displayString) → launch:\(app.name) [layer: \(currentLayer)]")
        } else {
            statusMessage = "Failed to save"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] saveCustomRule returned false")
        }

        isSaving = false
    }

    /// Select a system action for the output
    func selectSystemAction(_ action: SystemActionInfo) {
        selectedSystemAction = action
        selectedApp = nil // Clear any app selection
        outputSequence = nil // Clear any key sequence output
        outputLabel = action.name

        AppLogger.shared.log("⚙️ [MapperViewModel] Selected system action: \(action.name) (\(action.id))")

        // Auto-save if input is already set
        if let manager = kanataManager, inputSequence != nil {
            AppLogger.shared.log("⚙️ [MapperViewModel] Input already set, auto-saving...")
            Task {
                await saveSystemActionMapping(kanataManager: manager)
            }
        }
    }

    /// Save a mapping that triggers a system action
    private func saveSystemActionMapping(kanataManager: RuntimeCoordinator) async {
        AppLogger.shared.log("⚙️ [MapperViewModel] saveSystemActionMapping called")

        guard let inputSeq = inputSequence, let action = selectedSystemAction else {
            statusMessage = "Set input key first"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        let inputKanata = convertSequenceToKanataFormat(inputSeq)
        let targetLayer = layerFromString(currentLayer)

        AppLogger.shared.log("⚙️ [MapperViewModel] Creating rule: input='\(inputKanata)' output='\(action.kanataOutput)' layer=\(targetLayer)")

        var customRule = kanataManager.makeCustomRule(input: inputKanata, output: action.kanataOutput)
        customRule.notes = "\(action.name) [\(currentLayer) layer]"
        customRule.targetLayer = targetLayer

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        AppLogger.shared.log("⚙️ [MapperViewModel] saveCustomRule returned: \(success)")

        if success {
            lastSavedRuleID = customRule.id
            NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved system action: \(inputSeq.displayString) → \(action.name) [layer: \(currentLayer)]")
        } else {
            statusMessage = "Failed to save"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] saveCustomRule returned false")
        }

        isSaving = false
    }

    /// Convert layer name string to RuleCollectionLayer
    private func layerFromString(_ name: String) -> RuleCollectionLayer {
        let lowercased = name.lowercased()
        switch lowercased {
        case "base": return .base
        case "nav", "navigation": return .navigation
        default: return .custom(name)
        }
    }

    /// Convert KeySequence to kanata format string
    private func convertSequenceToKanataFormat(_ sequence: KeySequence) -> String {
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
}
