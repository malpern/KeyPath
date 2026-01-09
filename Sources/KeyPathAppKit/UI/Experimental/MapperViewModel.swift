import AppKit
import KeyPathCore
import SwiftUI

// MARK: - App Keymap Integration

/// Extension to integrate MapperViewModel with the per-app keymap system
extension MapperViewModel {
    /// Save a mapping that only applies when a specific app is active.
    /// Uses AppKeymapStore and AppConfigGenerator for virtual key-based app detection.
    ///
    /// - Returns: `true` if successful, `false` if failed. On failure, `statusMessage` is set with details.
    func saveAppSpecificMapping(
        inputKey: String,
        outputAction: String,
        appCondition: AppConditionInfo,
        kanataManager: RuntimeCoordinator
    ) async -> Bool {
        AppLogger.shared.log("🎯 [MapperViewModel] Saving app-specific mapping: \(inputKey) → \(outputAction) [only in \(appCondition.displayName)]")

        do {
            // 1. Load existing keymaps
            var existingKeymap = await AppKeymapStore.shared.getKeymap(bundleIdentifier: appCondition.bundleIdentifier)

            // 2. Create or update the keymap
            if existingKeymap == nil {
                // Create new keymap for this app
                existingKeymap = AppKeymap(
                    bundleIdentifier: appCondition.bundleIdentifier,
                    displayName: appCondition.displayName,
                    overrides: []
                )
                AppLogger.shared.log("🎯 [MapperViewModel] Created new app keymap for \(appCondition.displayName)")
            }

            guard var keymap = existingKeymap else {
                AppLogger.shared.error("❌ [MapperViewModel] Failed to create keymap")
                statusMessage = "Failed to create keymap"
                statusIsError = true
                return false
            }

            // 3. Add or update the override for this input key
            let newOverride = AppKeyOverride(
                inputKey: inputKey.lowercased(),
                outputAction: outputAction,
                description: "Created via Mapper"
            )

            // Remove existing override for same input key (if any)
            keymap.overrides.removeAll { $0.inputKey.lowercased() == inputKey.lowercased() }
            keymap.overrides.append(newOverride)

            // 4. Save to store
            try await AppKeymapStore.shared.upsertKeymap(keymap)

            // 5. Regenerate the app-specific config file (keypath-apps.kbd)
            try await AppConfigGenerator.regenerateFromStore()

            // 5.1. Regenerate the MAIN config to use @kp-* aliases for app-specific keys
            // Without this, the base layer uses plain 'a' instead of '@kp-a',
            // and the switch expression in keypath-apps.kbd is never reached.
            try await AppConfigGenerator.regenerateMainConfig()

            // 6. Ensure the include line is in the main config
            let migrationService = KanataConfigMigrationService()
            let mainConfigPath = WizardSystemPaths.userConfigPath
            if !migrationService.hasIncludeLine(configPath: mainConfigPath) {
                do {
                    try migrationService.prependIncludeLineIfMissing(to: mainConfigPath)
                    AppLogger.shared.log("✅ [MapperViewModel] Added include line for keypath-apps.kbd")
                } catch KanataConfigMigrationService.MigrationError.includeAlreadyPresent {
                    // Already present, ignore
                } catch {
                    AppLogger.shared.warn("⚠️ [MapperViewModel] Could not add include line: \(error)")
                    // Continue anyway - user may need to add it manually
                }
            }

            // 7. Update AppContextService with the new bundle-to-VK mapping
            await AppContextService.shared.reloadMappings()

            // 8. Reload Kanata to pick up the new config
            _ = await kanataManager.restartKanata(reason: "Per-app mapping saved")

            AppLogger.shared.log("✅ [MapperViewModel] Saved app-specific mapping successfully")

            // Navigate to App Rules tab in drawer to show the saved rule
            NotificationCenter.default.post(name: .switchToAppRulesTab, object: nil)

            return true
        } catch let error as AppConfigError {
            // Surface validation errors with specific details to the UI
            AppLogger.shared.error("❌ [MapperViewModel] App config error: \(error.userFacingMessage)")
            statusMessage = error.userFacingMessage
            statusIsError = true
            return false
        } catch {
            // Generic error - still surface to UI
            AppLogger.shared.error("❌ [MapperViewModel] Failed to save app-specific mapping: \(error)")
            statusMessage = "Failed to save: \(error.localizedDescription)"
            statusIsError = true
            return false
        }
    }

    /// Remove an app-specific mapping
    func removeAppSpecificMapping(
        inputKey: String,
        appCondition: AppConditionInfo
    ) async {
        AppLogger.shared.log("🗑️ [MapperViewModel] Removing app-specific mapping: \(inputKey) from \(appCondition.displayName)")

        do {
            guard var keymap = await AppKeymapStore.shared.getKeymap(bundleIdentifier: appCondition.bundleIdentifier) else {
                return
            }

            // Remove the override for this input key
            keymap.overrides.removeAll { $0.inputKey.lowercased() == inputKey.lowercased() }

            if keymap.overrides.isEmpty {
                // If no more overrides, remove the entire keymap
                try await AppKeymapStore.shared.removeKeymap(bundleIdentifier: appCondition.bundleIdentifier)
            } else {
                // Update with remaining overrides
                try await AppKeymapStore.shared.upsertKeymap(keymap)
            }

            // Regenerate config
            try await AppConfigGenerator.regenerateFromStore()
            await AppContextService.shared.reloadMappings()

            AppLogger.shared.log("✅ [MapperViewModel] Removed app-specific mapping")
        } catch {
            AppLogger.shared.error("❌ [MapperViewModel] Failed to remove app-specific mapping: \(error)")
        }
    }
}

// MapperActionTypes (AppLaunchInfo, AppConditionInfo, SystemActionInfo)
// are defined in MapperActionTypes.swift

// MARK: - Mapper View Model

@MainActor
class MapperViewModel: ObservableObject {
    @Published var inputLabel: String = "A"
    @Published var outputLabel: String = "A"
    @Published var isRecordingInput = false
    @Published var isRecordingOutput = false
    @Published var isSaving = false
    @Published var statusMessage: String?
    @Published var statusIsError = false
    @Published var currentLayer: String = "base"
    @Published private(set) var availableLayers: [String] = ["base", "nav"]
    /// Selected app for launch action (nil = normal key output)
    @Published var selectedApp: AppLaunchInfo?
    /// Selected system action (nil = normal key output)
    @Published var selectedSystemAction: SystemActionInfo?
    /// Selected URL for web URL mapping (nil = normal key output)
    @Published var selectedURL: String?
    /// Favicon for the selected URL
    @Published var selectedURLFavicon: NSImage?
    /// Whether the URL input dialog is visible
    @Published var showingURLDialog = false
    /// Text input for URL dialog
    @Published var urlInputText = ""
    /// Key code of the captured input (for overlay-style rendering)
    /// Default to 0 (A key) so the default state shows the A key selected
    @Published var inputKeyCode: UInt16? = 0
    /// Apps that have a mapping for the currently selected input key
    @Published var appsWithCurrentKeyMapping: [AppKeymap] = []

    // MARK: - App Condition (Delegated to AppConditionManager)

    /// Manager for app condition (precondition) selection
    @Published var appConditionManager = AppConditionManager()

    /// Legacy accessor for selectedAppCondition
    var selectedAppCondition: AppConditionInfo? {
        get { appConditionManager.selectedAppCondition }
        set { appConditionManager.selectedAppCondition = newValue }
    }

    // MARK: - Advanced Behavior (Delegated to AdvancedBehaviorManager)

    /// Manager for advanced key behaviors (hold, tap-dance, timing)
    /// Views should access advanced behavior properties through this manager.
    @Published var advancedBehavior = AdvancedBehaviorManager()

    // Legacy accessors for backward compatibility during migration
    // These delegate to advancedBehavior and will be removed once views are updated
    var showAdvanced: Bool {
        get { advancedBehavior.showAdvanced }
        set { advancedBehavior.showAdvanced = newValue }
    }

    var holdAction: String {
        get { advancedBehavior.holdAction }
        set { advancedBehavior.holdAction = newValue }
    }

    var doubleTapAction: String {
        get { advancedBehavior.doubleTapAction }
        set { advancedBehavior.doubleTapAction = newValue }
    }

    var tappingTerm: Int {
        get { advancedBehavior.tappingTerm }
        set { advancedBehavior.tappingTerm = newValue }
    }

    var isRecordingHold: Bool {
        get { advancedBehavior.isRecordingHold }
        set { advancedBehavior.isRecordingHold = newValue }
    }

    var isRecordingDoubleTap: Bool {
        get { advancedBehavior.isRecordingDoubleTap }
        set { advancedBehavior.isRecordingDoubleTap = newValue }
    }

    // Hold behavior type - use AdvancedBehaviorManager's type
    typealias HoldBehaviorType = AdvancedBehaviorManager.HoldBehaviorType

    var holdBehavior: HoldBehaviorType {
        get { advancedBehavior.holdBehavior }
        set { advancedBehavior.holdBehavior = newValue }
    }

    var customTapKeysText: String {
        get { advancedBehavior.customTapKeysText }
        set { advancedBehavior.customTapKeysText = newValue }
    }

    var tapDanceSteps: [(label: String, action: String, isRecording: Bool)] {
        get { advancedBehavior.tapDanceSteps }
        set { advancedBehavior.tapDanceSteps = newValue }
    }

    static let tapDanceLabels = AdvancedBehaviorManager.tapDanceLabels

    var showTimingAdvanced: Bool {
        get { advancedBehavior.showTimingAdvanced }
        set { advancedBehavior.showTimingAdvanced = newValue }
    }

    var tapTimeout: Int {
        get { advancedBehavior.tapTimeout }
        set { advancedBehavior.tapTimeout = newValue }
    }

    var holdTimeout: Int {
        get { advancedBehavior.holdTimeout }
        set { advancedBehavior.holdTimeout = newValue }
    }

    var showConflictDialog: Bool {
        get { advancedBehavior.showConflictDialog }
        set { advancedBehavior.showConflictDialog = newValue }
    }

    typealias ConflictType = AdvancedBehaviorManager.ConflictType

    var pendingConflictType: ConflictType? {
        get { advancedBehavior.pendingConflictType }
        set { advancedBehavior.pendingConflictType = newValue }
    }

    var pendingConflictField: String {
        get { advancedBehavior.pendingConflictField }
        set { advancedBehavior.pendingConflictField = newValue }
    }

    /// Default KeySequence for A key - used as initial value so save works without capturing input first
    private static let defaultAKeySequence = KeySequence(
        keys: [KeyPress(baseKey: "a", modifiers: [], keyCode: 0)],
        captureMode: .single
    )
    private var inputSequence: KeySequence? = MapperViewModel.defaultAKeySequence
    private var outputSequence: KeySequence? = MapperViewModel.defaultAKeySequence
    private var keyboardCapture: KeyboardCapture?
    private var kanataManager: RuntimeCoordinator?
    private var rulesManager: RuleCollectionsManager? { kanataManager?.rulesManager }
    private var finalizeTimer: Timer?
    /// ID of the last saved custom rule (for clearing/deleting)
    private var lastSavedRuleID: UUID?
    /// Original key context from overlay click (for reset after clear)
    var originalInputKey: String?
    private var originalOutputKey: String?
    private var originalAppIdentifier: String?
    private var originalSystemActionIdentifier: String?
    private var originalURL: String?
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
        inputSequence != nil && (outputSequence != nil || selectedApp != nil || selectedSystemAction != nil || selectedURL != nil)
    }

    func configure(kanataManager: RuntimeCoordinator) {
        self.kanataManager = kanataManager
        Task {
            await refreshAvailableLayers()
        }
    }

    /// Set the current layer
    func setLayer(_ layer: String) {
        currentLayer = layer
        AppLogger.shared.log("🗂️ [MapperViewModel] Layer set to: \(layer)")

        // Post notification for other views to update
        NotificationCenter.default.post(
            name: .kanataLayerChanged,
            object: nil,
            userInfo: ["layer": layer]
        )
    }

    /// Update input from a key click in the overlay (used by mapper drawer)
    func setInputFromKeyClick(
        keyCode: UInt16,
        inputLabel: String,
        outputLabel: String,
        appIdentifier: String? = nil,
        systemActionIdentifier: String? = nil,
        urlIdentifier: String? = nil
    ) {
        // Stop any active recording
        stopRecording()

        // Update input
        inputKeyCode = keyCode
        self.inputLabel = formatKeyForDisplay(inputLabel)
        inputSequence = KeySequence(
            keys: [KeyPress(baseKey: inputLabel, modifiers: [], keyCode: Int64(keyCode))],
            captureMode: .single
        )

        // Clear previous selections first (including app condition - revert to "Everywhere")
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil
        selectedAppCondition = nil

        // Set output based on action type
        if let appId = appIdentifier, let appInfo = appLaunchInfo(for: appId) {
            selectedApp = appInfo
            self.outputLabel = appInfo.name
            outputSequence = nil
            AppLogger.shared.log("🖱️ [MapperViewModel] Key click - app launch: \(inputLabel) -> \(appInfo.name)")
        } else if let urlId = urlIdentifier {
            selectedURL = urlId
            self.outputLabel = extractDomain(from: urlId)
            outputSequence = nil
            AppLogger.shared.log("🖱️ [MapperViewModel] Key click - URL: \(inputLabel) -> \(urlId)")
        } else if let systemId = systemActionIdentifier, let systemAction = SystemActionInfo.find(byOutput: systemId) {
            selectedSystemAction = systemAction
            self.outputLabel = systemAction.name
            outputSequence = nil
            AppLogger.shared.log("🖱️ [MapperViewModel] Key click - system action: \(inputLabel) -> \(systemAction.name)")
        } else {
            // Regular key mapping
            self.outputLabel = formatKeyForDisplay(outputLabel)
            outputSequence = KeySequence(
                keys: [KeyPress(baseKey: outputLabel, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
            AppLogger.shared.log("🖱️ [MapperViewModel] Key click - key mapping: \(inputLabel) -> \(outputLabel)")
        }

        // Update list of apps that have mappings for this key
        Task { await updateAppsWithMapping() }
    }

    /// Update the list of apps that have a mapping for the currently selected input key
    func updateAppsWithMapping() async {
        guard let keyCode = inputKeyCode else {
            appsWithCurrentKeyMapping = []
            return
        }
        let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)
        appsWithCurrentKeyMapping = await AppKeymapStore.shared.getAppsWithMapping(forInputKey: inputKey)
    }

    /// Apply preset values from overlay click
    func applyPresets(
        input: String,
        output: String,
        layer: String? = nil,
        inputKeyCode: UInt16? = nil,
        appIdentifier: String? = nil,
        systemActionIdentifier: String? = nil,
        urlIdentifier: String? = nil
    ) {
        // Stop any active recording
        stopRecording()

        // Store original context for reset after clear
        originalInputKey = input
        originalOutputKey = output
        originalAppIdentifier = appIdentifier
        originalSystemActionIdentifier = systemActionIdentifier
        originalURL = urlIdentifier
        originalLayer = layer

        // Clear any previously saved rule ID since we're starting fresh
        lastSavedRuleID = nil
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil

        // Set the layer
        if let layer {
            currentLayer = layer
        }

        // Set the input label and sequence
        inputLabel = formatKeyForDisplay(input)
        // Create simple key sequences for the presets
        // Use provided keyCode if available (from overlay), otherwise 0 as placeholder
        let keyCodeToUse = inputKeyCode ?? 0
        inputSequence = KeySequence(
            keys: [KeyPress(baseKey: input, modifiers: [], keyCode: Int64(keyCodeToUse))],
            captureMode: .single
        )

        if let appIdentifier, let appInfo = appLaunchInfo(for: appIdentifier) {
            selectedApp = appInfo
            outputLabel = appInfo.name
            outputSequence = nil
            AppLogger.shared.log("🗺️ [MapperViewModel] Preset output is app launch: \(appInfo.name)")
        } else if let urlIdentifier {
            selectedURL = urlIdentifier
            outputLabel = extractDomain(from: urlIdentifier)
            outputSequence = nil
            AppLogger.shared.log("🗺️ [MapperViewModel] Preset output is URL: \(urlIdentifier)")
        } else if let systemActionIdentifier,
                  let systemAction = SystemActionInfo.find(byOutput: systemActionIdentifier) {
            // It's a system action/media key - set selectedSystemAction for SF Symbol rendering
            selectedSystemAction = systemAction
            outputLabel = systemAction.name
            outputSequence = nil
            AppLogger.shared.log("🗺️ [MapperViewModel] Preset output is system action: \(systemAction.name)")
        } else if let systemAction = SystemActionInfo.find(byOutput: output) {
            // Fallback: resolve by output label
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

        // Store the keyCode for proper keycap rendering
        if let inputKeyCode {
            self.inputKeyCode = inputKeyCode
        }

        statusMessage = nil
        statusIsError = false

        AppLogger.shared.log("📝 [MapperViewModel] Applied presets: \(input) → \(output) [layer: \(currentLayer)] [inputKeyCode: \(keyCodeToUse)]")
    }

    /// Format a kanata key name for display (e.g., "leftmeta" -> "⌘")
    /// Uses the centralized KeyDisplayFormatter utility.
    private func formatKeyForDisplay(_ key: String) -> String {
        AppLogger.shared.log("🔤 [MapperViewModel] formatKeyForDisplay input: '\(key)'")
        let result = KeyDisplayFormatter.format(key)
        AppLogger.shared.log("🔤 [MapperViewModel] formatKeyForDisplay output: '\(result)'")
        return result
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

    func toggleHoldRecording() {
        // Check for conflict: if tap-dance is set, show conflict dialog
        if checkHoldConflict() {
            pendingConflictType = .holdVsTapDance
            pendingConflictField = "hold"
            showConflictDialog = true
            return
        }

        if isRecordingHold {
            isRecordingHold = false
        } else {
            // Stop any other recording
            stopRecording()
            isRecordingHold = true
            startSimpleKeyCapture { [weak self] keyName in
                self?.holdAction = keyName
                self?.isRecordingHold = false
            }
        }
    }

    func toggleDoubleTapRecording() {
        // Check for conflict: if hold is set, show conflict dialog
        if !holdAction.isEmpty {
            pendingConflictType = .holdVsTapDance
            pendingConflictField = "doubleTap"
            showConflictDialog = true
            return
        }

        if isRecordingDoubleTap {
            isRecordingDoubleTap = false
        } else {
            // Stop any other recording
            stopRecording()
            isRecordingDoubleTap = true
            startSimpleKeyCapture { [weak self] keyName in
                self?.doubleTapAction = keyName
                self?.isRecordingDoubleTap = false
            }
        }
    }

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

        // Check for conflict: if hold is set, show conflict dialog
        if !holdAction.isEmpty {
            pendingConflictType = .holdVsTapDance
            pendingConflictField = "tapDance-\(index)"
            showConflictDialog = true
            return
        }

        if tapDanceSteps[index].isRecording {
            tapDanceSteps[index].isRecording = false
        } else {
            // Stop any other recording
            stopRecording()
            tapDanceSteps[index].isRecording = true
            startSimpleKeyCapture { [weak self] keyName in
                guard let self, index < tapDanceSteps.count else { return }
                tapDanceSteps[index].action = keyName
                tapDanceSteps[index].isRecording = false
            }
        }
    }

    /// Clear tap-dance step action at index
    func clearTapDanceStep(at index: Int) {
        advancedBehavior.clearTapDanceStep(at: index)
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

    /// Simple single-key capture for hold/double-tap/tap-dance actions
    private func startSimpleKeyCapture(onCapture: @escaping (String) -> Void) {
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Escape cancels recording
            if event.keyCode == 53 {
                self?.stopAllRecording()
                if let m = monitor { NSEvent.removeMonitor(m) }
                return nil
            }

            let keyName = Self.keyNameFromEvent(event)
            onCapture(keyName)
            if let m = monitor { NSEvent.removeMonitor(m) }
            return nil
        }

        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            let isAnyRecording = isRecordingHold || isRecordingDoubleTap || tapDanceSteps.contains { $0.isRecording }
            if isAnyRecording {
                stopAllRecording()
                if let m = monitor { NSEvent.removeMonitor(m) }
            }
        }
    }

    /// Stop all recording states
    private func stopAllRecording() {
        advancedBehavior.stopAllRecording()
    }

    /// Convert key event to kanata key name
    private static func keyNameFromEvent(_ event: NSEvent) -> String {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags

        var prefix = ""
        if modifiers.contains(.command) { prefix += "M-" }
        if modifiers.contains(.control) { prefix += "C-" }
        if modifiers.contains(.option) { prefix += "A-" }
        if modifiers.contains(.shift) { prefix += "S-" }

        let keyName = switch keyCode {
        case 0: "a"
        case 1: "s"
        case 2: "d"
        case 3: "f"
        case 4: "h"
        case 5: "g"
        case 6: "z"
        case 7: "x"
        case 8: "c"
        case 9: "v"
        case 11: "b"
        case 12: "q"
        case 13: "w"
        case 14: "e"
        case 15: "r"
        case 16: "y"
        case 17: "t"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 22: "6"
        case 23: "5"
        case 24: "="
        case 25: "9"
        case 26: "7"
        case 27: "-"
        case 28: "8"
        case 29: "0"
        case 30: "]"
        case 31: "o"
        case 32: "u"
        case 33: "["
        case 34: "i"
        case 35: "p"
        case 36: "ret"
        case 37: "l"
        case 38: "j"
        case 39: "'"
        case 40: "k"
        case 41: ";"
        case 42: "\\"
        case 43: ","
        case 44: "/"
        case 45: "n"
        case 46: "m"
        case 47: "."
        case 48: "tab"
        case 49: "spc"
        case 50: "`"
        case 51: "bspc"
        case 53: "esc"
        case 55: "lmet"
        case 56: "lsft"
        case 57: "caps"
        case 58: "lalt"
        case 59: "lctl"
        case 60: "rsft"
        case 61: "ralt"
        case 62: "rctl"
        case 63: "fn"
        case 96: "f5"
        case 97: "f6"
        case 98: "f7"
        case 99: "f3"
        case 100: "f8"
        case 101: "f9"
        case 103: "f11"
        case 105: "f13"
        case 107: "f14"
        case 109: "f10"
        case 111: "f12"
        case 113: "f15"
        case 118: "f4"
        case 119: "end"
        case 120: "f2"
        case 121: "pgdn"
        case 122: "f1"
        case 123: "left"
        case 124: "right"
        case 125: "down"
        case 126: "up"
        default: "k\(keyCode)"
        }

        return prefix + keyName
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
        selectedURL = nil

        let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)

        // Look up the current mapping from the overlay controller
        if let mapping = LiveKeyboardOverlayController.shared.lookupCurrentMapping(forKeyCode: keyCode) {
            let info = mapping.info

            if let appIdentifier = info.appLaunchIdentifier,
               let appInfo = appLaunchInfo(for: appIdentifier) {
                selectedApp = appInfo
                outputLabel = appInfo.name
                outputSequence = nil
                originalAppIdentifier = appIdentifier
                originalSystemActionIdentifier = nil
                originalURL = nil
                AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) is app launch: \(appInfo.name)")
            } else if let url = info.urlIdentifier {
                selectedURL = url
                outputLabel = extractDomain(from: url)
                outputSequence = nil
                originalURL = url
                originalAppIdentifier = nil
                originalSystemActionIdentifier = nil
                AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) is URL: \(url)")
            } else if let systemId = info.systemActionIdentifier,
                      let systemAction = SystemActionInfo.find(byOutput: systemId) ?? SystemActionInfo.find(byOutput: info.displayLabel) {
                selectedSystemAction = systemAction
                outputLabel = systemAction.name
                outputSequence = nil
                originalSystemActionIdentifier = systemId
                originalAppIdentifier = nil
                originalURL = nil
                AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) is system action: \(systemAction.name)")
            } else if let outputKey = info.outputKey {
                outputLabel = formatKeyForDisplay(outputKey)
                outputSequence = KeySequence(
                    keys: [KeyPress(baseKey: outputKey, modifiers: [], keyCode: 0)],
                    captureMode: .single
                )
                originalAppIdentifier = nil
                originalSystemActionIdentifier = nil
                originalURL = nil
            } else {
                // Fallback: use displayLabel as the output key
                outputLabel = info.displayLabel
                let outputKey = info.displayLabel.lowercased()
                outputSequence = KeySequence(
                    keys: [KeyPress(baseKey: outputKey, modifiers: [], keyCode: 0)],
                    captureMode: .single
                )
                originalAppIdentifier = nil
                originalSystemActionIdentifier = nil
                originalURL = nil
            }

            // Store original context for reset
            originalInputKey = inputKey
            originalOutputKey = info.outputKey ?? info.displayLabel
            originalLayer = mapping.layer
            currentLayer = mapping.layer

            AppLogger.shared.log("🔍 [MapperViewModel] Key \(keyCode) maps to: \(outputLabel) in layer \(currentLayer)")
        } else {
            // No mapping found - default to key maps to itself
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

        // Auto-save when input is captured and we have either output or app/system action/URL
        if canSave, let manager = kanataManager {
            Task {
                if selectedURL != nil {
                    // URL mapping
                    AppLogger.shared.log("🎯 [MapperViewModel] Calling saveURLMapping")
                    await saveURLMapping(kanataManager: manager)
                } else if selectedApp != nil {
                    // App launch mapping
                    AppLogger.shared.log("🎯 [MapperViewModel] Calling saveAppLaunchMapping")
                    await saveAppLaunchMapping(kanataManager: manager)
                } else if selectedSystemAction != nil {
                    // System action mapping
                    AppLogger.shared.log("🎯 [MapperViewModel] Calling saveSystemActionMapping")
                    await saveSystemActionMapping(kanataManager: manager)
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
            inputLabel = "A"
            inputKeyCode = 0 // Default to A key
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
                // No saved state, default to "A"
                outputLabel = "A"
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

        // Skip identity mappings (A→A) - no point in saving a rule that does nothing
        // Also skip if user hasn't changed anything from defaults
        let inputKey = convertSequenceToKanataFormat(inputSeq).lowercased()
        let outputKey = convertSequenceToKanataFormat(outputSeq).lowercased()
        if inputKey == outputKey, selectedApp == nil, selectedSystemAction == nil, selectedURL == nil {
            statusMessage = "Nothing to save - input and output are the same"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        // Check if this is an app-specific mapping
        if let appCondition = selectedAppCondition {
            let inputKanata = convertSequenceToKanataFormat(inputSeq)
            let outputKanata = convertSequenceToKanataFormat(outputSeq)

            let success = await saveAppSpecificMapping(
                inputKey: inputKanata,
                outputAction: outputKanata,
                appCondition: appCondition,
                kanataManager: kanataManager
            )

            if success {
                statusMessage = "✓ Saved"
                statusIsError = false
                SoundPlayer.shared.playSuccessSound()
                AppLogger.shared.log("✅ [MapperViewModel] Saved app-specific mapping: \(inputSeq.displayString) → \(outputSeq.displayString) [only in \(appCondition.displayName)]")
            } else {
                statusMessage = "Failed to save app-specific rule"
                statusIsError = true
            }

            isSaving = false
            return
        }

        // Global mapping (no app condition)
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

            let customRuleSaved = await kanataManager.saveCustomRule(customRule, skipReload: true)
            AppLogger.shared.log("💾 [MapperViewModel] saveCustomRule returned: \(customRuleSaved)")

            if customRuleSaved {
                // Track the saved rule ID for potential clearing
                lastSavedRuleID = customRule.id

                // Notify overlay to rebuild layer mapping (since saveGeneratedConfiguration
                // doesn't go through onRulesChanged, we post the notification explicitly)
                AppLogger.shared.info("🔔 [MapperViewModel] Posting kanataConfigChanged notification (input='\(inputKanata)', output='\(outputKanata)', layer='\(targetLayer)')")
                NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)

                statusMessage = "✓ Saved"
                statusIsError = false
                AppLogger.shared.log("✅ [MapperViewModel] Saved mapping: \(inputSeq.displayString) → \(outputSeq.displayString) [layer: \(currentLayer)] (ruleID: \(customRule.id))")
            } else {
                // Custom rule save failed (validation or conflict)
                statusMessage = "Rule save failed"
                statusIsError = true
                AppLogger.shared.error("❌ [MapperViewModel] saveCustomRule returned false for input='\(inputKanata)', output='\(outputKanata)'")
            }
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] Save failed: \(error)")
        }

        isSaving = false
    }

    private func reset() {
        inputLabel = "A"
        outputLabel = "A"
        inputKeyCode = 0 // Default to A key
        // Reset to default A key sequences so save works without capturing input first
        inputSequence = Self.defaultAKeySequence
        outputSequence = Self.defaultAKeySequence
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil
        selectedAppCondition = nil
        statusMessage = nil
    }

    /// Reset for a new mapping but preserve selectedAppCondition
    /// Used when adding a new rule to a specific app
    func resetForNewMapping() {
        inputLabel = "A"
        outputLabel = "A"
        inputKeyCode = 0 // Default to A key
        inputSequence = Self.defaultAKeySequence
        outputSequence = Self.defaultAKeySequence
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil
        // Keep selectedAppCondition - don't reset it
        statusMessage = nil
    }

    /// Clear all values, delete the saved rule, and reset to original key context (or default)
    func clear() {
        stopRecording()
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil

        // Delete the saved rule if we have one, otherwise try to resolve by input
        if let manager = kanataManager {
            if let ruleID = lastSavedRuleID {
                Task {
                    await manager.removeCustomRule(withID: ruleID)
                    // Note: .kanataConfigChanged notification is posted by onRulesChanged callback
                    AppLogger.shared.log("🧹 [MapperViewModel] Deleted rule \(ruleID)")
                }
                lastSavedRuleID = nil
            } else if let inputKanata = currentInputKanataString() {
                // Use makeCustomRule to reuse existing rule ID for this input (if any)
                let probeRule = manager.makeCustomRule(input: inputKanata, output: "xx")
                Task {
                    await manager.removeCustomRule(withID: probeRule.id)
                    AppLogger.shared.log("🧹 [MapperViewModel] Deleted rule by input \(inputKanata) (id: \(probeRule.id))")
                }
            }
        }

        // Reset to original key context if opened from overlay, otherwise default
        if let origInput = originalInputKey, let origOutput = originalOutputKey {
            // Re-apply the original presets
            inputLabel = formatKeyForDisplay(origInput)
            inputSequence = KeySequence(
                keys: [KeyPress(baseKey: origInput, modifiers: [], keyCode: 0)],
                captureMode: .single
            )

            if let appIdentifier = originalAppIdentifier,
               let appInfo = appLaunchInfo(for: appIdentifier) {
                selectedApp = appInfo
                outputLabel = appInfo.name
                outputSequence = nil
            } else if let url = originalURL {
                selectedURL = url
                outputLabel = extractDomain(from: url)
                outputSequence = nil
            } else if let systemActionId = originalSystemActionIdentifier,
                      let systemAction = SystemActionInfo.find(byOutput: systemActionId) {
                selectedSystemAction = systemAction
                outputLabel = systemAction.name
                outputSequence = nil
            } else if let systemAction = SystemActionInfo.find(byOutput: origOutput) {
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

    /// Revert to keystroke mode - clears any actions and resets output to match input
    /// Used when switching from system action/app/URL back to plain keystroke
    func revertToKeystroke() {
        stopRecording()

        // Clear all actions
        selectedApp = nil
        selectedSystemAction = nil
        selectedURL = nil

        // Reset output to match input (identity mapping: A→A)
        outputLabel = inputLabel
        outputSequence = inputSequence

        // Delete the saved rule if we have one
        if let manager = kanataManager {
            if let ruleID = lastSavedRuleID {
                Task {
                    await manager.removeCustomRule(withID: ruleID)
                    // Post notification to update keyboard
                    NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
                    AppLogger.shared.log("🧹 [MapperViewModel] Reverted to keystroke, deleted rule \(ruleID)")
                }
                lastSavedRuleID = nil
            } else if let inputKanata = currentInputKanataString() {
                // Try to delete by input key
                let probeRule = manager.makeCustomRule(input: inputKanata, output: "xx")
                Task {
                    await manager.removeCustomRule(withID: probeRule.id)
                    // Post notification to update keyboard
                    NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)
                    AppLogger.shared.log("🧹 [MapperViewModel] Reverted to keystroke, deleted rule by input \(inputKanata)")
                }
            }
        }

        statusMessage = "✓ Reverted to keystroke"
    }

    /// Reset entire keyboard by clearing all custom rules (preserves rule collections)
    func resetAllToDefaults(kanataManager: RuntimeCoordinator) async {
        stopRecording()

        // Clear all custom rules but preserve rule collections
        await kanataManager.clearAllCustomRules()

        // Reset local state
        reset()
        lastSavedRuleID = nil
        originalInputKey = nil
        originalOutputKey = nil
        originalLayer = nil
        currentLayer = "base"

        // Post notification to update keyboard
        NotificationCenter.default.post(name: .kanataConfigChanged, object: nil)

        statusMessage = "✓ Custom rules cleared"
        statusIsError = false
        AppLogger.shared.log("🔄 [MapperViewModel] Cleared all custom rules (collections preserved)")
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

    private func appLaunchInfo(for identifier: String) -> AppLaunchInfo? {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: identifier) {
            return buildAppLaunchInfo(from: url)
        }

        // Fallback: treat identifier as an app name and look in common locations.
        let candidates = [
            URL(fileURLWithPath: "/Applications/\(identifier).app"),
            URL(fileURLWithPath: "/System/Applications/\(identifier).app")
        ]

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return buildAppLaunchInfo(from: url)
        }

        return nil
    }

    private func buildAppLaunchInfo(from url: URL) -> AppLaunchInfo {
        let appName = url.deletingPathExtension().lastPathComponent
        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64) // Reasonable size for display

        return AppLaunchInfo(
            name: appName,
            bundleIdentifier: bundleIdentifier,
            icon: icon
        )
    }

    /// Process the selected app and update output
    private func handleSelectedApp(at url: URL) {
        let appInfo = buildAppLaunchInfo(from: url)

        selectedApp = appInfo
        selectedSystemAction = nil // Clear any system action selection
        selectedURL = nil
        outputLabel = appInfo.name
        outputSequence = nil // Clear any key sequence output

        AppLogger.shared.log("📱 [MapperViewModel] Selected app: \(appInfo.name) (\(appInfo.bundleIdentifier ?? "no bundle ID"))")
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

    // MARK: - App Condition (Precondition) - Delegated to AppConditionManager

    /// Get list of currently running apps for the condition picker
    func getRunningApps() -> [AppConditionInfo] {
        appConditionManager.getRunningApps()
    }

    /// Open file picker to select an app for the condition (precondition)
    func pickAppCondition() {
        appConditionManager.pickAppCondition()
    }

    /// Clear the app condition
    func clearAppCondition() {
        appConditionManager.clearAppCondition()
    }

    // MARK: - Layer Management

    /// System layers that cannot be deleted
    private static let systemLayers: Set<String> = ["base", "nav", "navigation"]

    /// Get list of available layers (system + custom).
    /// Uses cached layer names refreshed from Kanata + rule collections.
    func getAvailableLayers() -> [String] {
        if availableLayers.isEmpty {
            return buildAvailableLayers(additional: [])
        }
        return availableLayers
    }

    /// Refresh cached layer names using RuntimeCoordinator + local rule collections.
    func refreshAvailableLayers() async {
        let tcpLayers = await kanataManager?.fetchLayerNamesFromKanata() ?? []
        let nextLayers = buildAvailableLayers(additional: tcpLayers)
        await MainActor.run {
            availableLayers = nextLayers
        }
    }

    private func buildAvailableLayers(additional: [String]) -> [String] {
        var layers = Set<String>(["base", "nav"])

        for layer in additional {
            layers.insert(layer.lowercased())
        }

        if let rulesManager {
            // Add layers from enabled rule collections
            for collection in rulesManager.ruleCollections where collection.isEnabled {
                layers.insert(collection.targetLayer.kanataName)
            }

            // Add layers from enabled custom rules
            for rule in rulesManager.customRules where rule.isEnabled {
                layers.insert(rule.targetLayer.kanataName)
            }
        }

        // Sort with system layers first, then alphabetically
        return layers.sorted { lhs, rhs in
            let lhsSystem = Self.systemLayers.contains(lhs.lowercased())
            let rhsSystem = Self.systemLayers.contains(rhs.lowercased())
            if lhsSystem != rhsSystem { return lhsSystem }
            return lhs < rhs
        }
    }

    /// Check if a layer is a system layer (cannot be deleted)
    func isSystemLayer(_ layer: String) -> Bool {
        Self.systemLayers.contains(layer.lowercased())
    }

    /// Create a new layer with persistence and Leader key activator
    func createLayer(_ name: String) {
        guard !name.isEmpty else { return }

        // Sanitize the layer name
        let sanitizedName = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }

        guard !sanitizedName.isEmpty else { return }

        // Check for duplicates
        let existingLayers = getAvailableLayers()
        if existingLayers.contains(where: { $0.lowercased() == sanitizedName }) {
            AppLogger.shared.warn("⚠️ [MapperViewModel] Layer already exists: \(sanitizedName)")
            setLayer(sanitizedName)
            return
        }

        // Create a RuleCollection for this layer with Leader key activator
        // Activator: first letter of layer name, from nav layer (Leader → letter)
        let activatorKey = String(sanitizedName.prefix(1))
        let targetLayer = RuleCollectionLayer.custom(sanitizedName)

        let collection = RuleCollection(
            id: UUID(),
            name: sanitizedName.capitalized,
            summary: "Custom layer: \(sanitizedName)",
            category: .custom,
            mappings: [],
            isEnabled: true,
            icon: "square.stack.3d.up",
            tags: ["custom-layer"],
            targetLayer: targetLayer,
            momentaryActivator: MomentaryActivator(
                input: activatorKey,
                targetLayer: targetLayer,
                sourceLayer: .navigation
            ),
            activationHint: "Leader → \(activatorKey.uppercased())",
            configuration: .list
        )

        // Persist via rulesManager
        if let rulesManager {
            Task {
                await rulesManager.addCollection(collection)
                AppLogger.shared.log("📚 [MapperViewModel] Created new layer: \(sanitizedName) (Leader → \(activatorKey.uppercased()))")
                await refreshAvailableLayers()
            }
        }

        // Switch to the new layer
        setLayer(sanitizedName)
    }

    /// Delete a layer and all associated rules (only non-system layers)
    func deleteLayer(_ layer: String) {
        guard !isSystemLayer(layer) else {
            AppLogger.shared.warn("⚠️ [MapperViewModel] Cannot delete system layer: \(layer)")
            return
        }

        // If we're on this layer, switch to base first
        if currentLayer.lowercased() == layer.lowercased() {
            setLayer("base")
        }

        // Remove all collections and rules for this layer
        if let rulesManager {
            Task {
                await rulesManager.removeLayer(layer)
                AppLogger.shared.log("🗑️ [MapperViewModel] Deleted layer: \(layer)")
                await refreshAvailableLayers()
            }
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
            // Note: .kanataConfigChanged notification is posted by onRulesChanged callback
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
        selectedURL = nil
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
            // Note: .kanataConfigChanged notification is posted by onRulesChanged callback
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

    /// Show the URL input dialog
    func showURLInputDialog() {
        urlInputText = "https://"
        showingURLDialog = true
    }

    /// Submit the URL from the input dialog
    func submitURL() {
        let trimmed = urlInputText.trimmingCharacters(in: .whitespaces)

        // Validate URL (no spaces, not empty, not just "https://")
        guard !trimmed.isEmpty, !trimmed.contains(" "), trimmed != "https://", trimmed != "http://" else {
            statusMessage = "Invalid URL"
            statusIsError = true
            return
        }

        selectedURL = trimmed
        selectedApp = nil // Clear any app selection
        selectedSystemAction = nil // Clear any system action selection
        outputSequence = nil // Clear any key sequence output
        outputLabel = extractDomain(from: trimmed)
        selectedURLFavicon = nil // Clear old favicon while loading
        showingURLDialog = false

        AppLogger.shared.log("🌐 [MapperViewModel] Selected URL: \(trimmed)")

        // Fetch favicon asynchronously
        Task {
            let favicon = await FaviconFetcher.shared.fetchFavicon(for: trimmed)
            await MainActor.run {
                self.selectedURLFavicon = favicon
                if favicon != nil {
                    AppLogger.shared.log("🖼️ [MapperViewModel] Loaded favicon for \(trimmed)")
                }
            }
        }

        // Auto-save if input is already set
        if let manager = kanataManager, inputSequence != nil {
            AppLogger.shared.log("🌐 [MapperViewModel] Input already set, auto-saving...")
            Task {
                await saveURLMapping(kanataManager: manager)
            }
        }
    }

    /// Save a mapping that opens a web URL
    private func saveURLMapping(kanataManager: RuntimeCoordinator) async {
        AppLogger.shared.log("🌐 [MapperViewModel] saveURLMapping called")

        guard let inputSeq = inputSequence, let url = selectedURL else {
            AppLogger.shared.log("⚠️ [MapperViewModel] saveURLMapping: missing input or URL")
            statusMessage = "Set input key first"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        let inputKanata = convertSequenceToKanataFormat(inputSeq)
        let outputKanata = "(push-msg \"open:\(url)\")"
        let targetLayer = layerFromString(currentLayer)

        AppLogger.shared.log("🌐 [MapperViewModel] Creating rule: input='\(inputKanata)' output='\(outputKanata)' layer=\(targetLayer)")

        var customRule = kanataManager.makeCustomRule(input: inputKanata, output: outputKanata)
        customRule.notes = "Open \(url) [\(currentLayer) layer]"
        customRule.targetLayer = targetLayer

        let success = await kanataManager.saveCustomRule(customRule, skipReload: false)
        AppLogger.shared.log("🌐 [MapperViewModel] saveCustomRule returned: \(success)")

        if success {
            lastSavedRuleID = customRule.id
            statusMessage = "✓ Saved"
            statusIsError = false
            AppLogger.shared.log("✅ [MapperViewModel] Saved URL mapping: \(inputSeq.displayString) → open:\(url) [layer: \(currentLayer)]")

            // Trigger favicon fetch (fire-and-forget)
            Task { _ = await FaviconFetcher.shared.fetchFavicon(for: url) }
        } else {
            statusMessage = "Failed to save"
            statusIsError = true
            AppLogger.shared.error("❌ [MapperViewModel] saveCustomRule returned false")
        }

        isSaving = false
    }

    /// Extract domain from URL for display purposes
    private func extractDomain(from url: String) -> String {
        KeyMappingFormatter.extractDomain(from: url)
    }

    // MARK: - Kanata Format Conversion (Delegated to KeyMappingFormatter)

    /// Convert layer name string to RuleCollectionLayer
    private func layerFromString(_ name: String) -> RuleCollectionLayer {
        KeyMappingFormatter.layerFromString(name)
    }

    /// Convert KeySequence to kanata format string
    private func convertSequenceToKanataFormat(_ sequence: KeySequence) -> String {
        KeyMappingFormatter.toKanataFormat(sequence)
    }

    /// Best-effort input kanata string for rule removal
    private func currentInputKanataString() -> String? {
        if let inputSeq = inputSequence {
            return convertSequenceToKanataFormat(inputSeq)
        }
        if let origInput = originalInputKey {
            let seq = KeySequence(
                keys: [KeyPress(baseKey: origInput, modifiers: [], keyCode: 0)],
                captureMode: .single
            )
            return convertSequenceToKanataFormat(seq)
        }
        return nil
    }
}
