import AppKit
import Combine
import KeyPathCore
import SwiftUI

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
    @Published var availableLayers: [String] = ["base", "nav"]
    /// Selected app for launch action (nil = normal key output)
    @Published var selectedApp: AppLaunchInfo?
    /// Selected system action (nil = normal key output)
    @Published var selectedSystemAction: SystemActionInfo?
    /// Selected URL for web URL mapping (nil = normal key output)
    @Published var selectedURL: String? {
        didSet {
            if selectedURL != oldValue {
                selectedURLFavicon = nil
            }
        }
    }

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

    init() {
        advancedBehaviorCancellable = advancedBehavior.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Legacy accessors for backward compatibility during migration
    /// These delegate to advancedBehavior and will be removed once views are updated
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

    var macroBehavior: MacroBehavior? {
        get { advancedBehavior.macroBehavior }
        set { advancedBehavior.macroBehavior = newValue }
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

    var isRecordingComboOutput: Bool {
        get { advancedBehavior.isRecordingComboOutput }
        set { advancedBehavior.isRecordingComboOutput = newValue }
    }

    var isRecordingMacro: Bool {
        get { advancedBehavior.isRecordingMacro }
        set { advancedBehavior.isRecordingMacro = newValue }
    }

    var comboOutput: String {
        get { advancedBehavior.comboOutput }
        set { advancedBehavior.comboOutput = newValue }
    }

    var comboKeys: [String] {
        get { advancedBehavior.comboKeys }
        set { advancedBehavior.comboKeys = newValue }
    }

    /// Hold behavior type - use AdvancedBehaviorManager's type
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
    static let defaultAKeySequence = KeySequence(
        keys: [KeyPress(baseKey: "a", modifiers: [], keyCode: 0)],
        captureMode: .single
    )
    var inputSequence: KeySequence? = MapperViewModel.defaultAKeySequence
    var outputSequence: KeySequence? = MapperViewModel.defaultAKeySequence
    var keyboardCapture: KeyboardCapture?
    var simpleKeyCaptureMonitor: Any?
    var simpleKeyCaptureToken: UUID?
    var multiTapFinalizeTimer: Timer?
    var multiTapPendingSequence: KeySequence?
    var multiTapUpdateHandler: ((String) -> Void)?
    var multiTapFinalizeHandler: ((String) -> Void)?
    var multiTapStopHandler: (() -> Void)?
    var advancedBehaviorCancellable: AnyCancellable?
    var kanataManager: RuntimeCoordinator?
    var rulesManager: RuleCollectionsManager? {
        kanataManager?.rulesManager
    }

    var finalizeTimer: Timer?
    /// ID of the last saved custom rule (for clearing/deleting)
    var lastSavedRuleID: UUID?
    /// Original key context from overlay click (for reset after clear)
    var originalInputKey: String?
    var originalOutputKey: String?
    var originalAppIdentifier: String?
    var originalSystemActionIdentifier: String?
    var originalURL: String?
    /// Original layer from overlay click
    var originalLayer: String?

    /// State saved before starting output recording (for restore on cancel)
    var savedOutputLabel: String?
    var savedOutputSequence: KeySequence?
    var savedSelectedApp: AppLaunchInfo?
    var savedSelectedSystemAction: SystemActionInfo?
    var savedMacroBehavior: MacroBehavior?

    /// Delay before finalizing a sequence capture (allows for multi-key sequences)
    let sequenceFinalizeDelay: TimeInterval = 0.8

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

        // Clear previous behavior (will be loaded separately via loadBehaviorFromExistingRule)
        advancedBehavior.holdAction = ""
        advancedBehavior.doubleTapAction = ""
        advancedBehavior.macroBehavior = nil
        advancedBehavior.comboKeys = []
        advancedBehavior.comboOutput = ""
        advancedBehavior.holdBehavior = .basic
        advancedBehavior.tapTimeout = 200
        advancedBehavior.holdTimeout = 200
        advancedBehavior.customTapKeysText = ""
    }

    /// Load behavior from existing custom rule for the current input key
    /// Call this after setInputFromKeyClick to restore hold/tap-dance settings
    func loadBehaviorFromExistingRule(kanataManager: RuntimeCoordinator) {
        guard let keyCode = inputKeyCode else { return }
        let inputKey = OverlayKeyboardView.keyCodeToKanataName(keyCode)

        // Look up existing rule
        guard let existingRule = kanataManager.getCustomRule(forInput: inputKey),
              let behavior = existingRule.behavior
        else {
            AppLogger.shared.log("📖 [MapperViewModel] No existing behavior for input '\(inputKey)'")
            return
        }

        switch behavior {
        case let .dualRole(dualRole):
            advancedBehavior.holdAction = dualRole.holdAction
            advancedBehavior.tapTimeout = dualRole.tapTimeout
            advancedBehavior.holdTimeout = dualRole.holdTimeout

            // Determine hold behavior type from flags
            if dualRole.activateHoldOnOtherKey {
                advancedBehavior.holdBehavior = .triggerEarly
            } else if dualRole.quickTap {
                advancedBehavior.holdBehavior = .quickTap
            } else if !dualRole.customTapKeys.isEmpty {
                advancedBehavior.holdBehavior = .customKeys
                advancedBehavior.customTapKeysText = dualRole.customTapKeys.joined(separator: " ")
            } else {
                advancedBehavior.holdBehavior = .basic
            }

            AppLogger.shared.log("📖 [MapperViewModel] Loaded dualRole behavior for '\(inputKey)': hold='\(dualRole.holdAction)'")

        case let .tapOrTapDance(tapBehavior):
            switch tapBehavior {
            case .tap:
                AppLogger.shared.log("📖 [MapperViewModel] Loaded tap behavior for '\(inputKey)'")
            case let .tapDance(tapDance):
                // Load timing
                advancedBehavior.tapTimeout = tapDance.windowMs

                // Load tap-dance steps
                // First step (index 0) is single tap - already loaded in outputLabel
                if tapDance.steps.count > 1 {
                    advancedBehavior.doubleTapAction = tapDance.steps[1].action
                }
                // Load additional steps into tapDanceSteps array (triple tap, quad tap, etc.)
                if tapDance.steps.count > 2 {
                    advancedBehavior.tapDanceSteps = tapDance.steps.dropFirst(2).map { step in
                        (label: step.label, action: step.action, isRecording: false)
                    }
                }

                AppLogger.shared.log("📖 [MapperViewModel] Loaded tapDance behavior for '\(inputKey)': \(tapDance.steps.count) steps, windowMs=\(tapDance.windowMs)")
            }

        case let .macro(macro):
            advancedBehavior.macroBehavior = macro
            AppLogger.shared.log("📖 [MapperViewModel] Loaded macro behavior for '\(inputKey)'")

        case let .chord(chord):
            // Load chord: remove the input key from the keys list (it's implicit)
            advancedBehavior.comboKeys = chord.keys.filter { $0.lowercased() != inputKey.lowercased() }
            advancedBehavior.comboOutput = chord.output
            advancedBehavior.comboTimeout = chord.timeout

            AppLogger.shared.log("📖 [MapperViewModel] Loaded chord behavior for '\(inputKey)': keys=\(chord.keys), output='\(chord.output)'")
        }
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
    func formatKeyForDisplay(_ key: String) -> String {
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
            stopSimpleKeyCapture()
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
        // Clear macro if needed
        if macroBehavior?.isValid == true {
            macroBehavior = nil
        }

        // Check for conflict: if hold is set, show conflict dialog
        if advancedBehavior.checkTapDanceConflict() {
            pendingConflictType = .holdVsTapDance
            pendingConflictField = "doubleTap"
            showConflictDialog = true
            return
        }

        if isRecordingDoubleTap {
            isRecordingDoubleTap = false
            stopMultiTapSequenceCapture(finalize: true)
        } else {
            // Stop any other recording
            stopRecording()
            stopAllRecording()
            isRecordingDoubleTap = true
            startMultiTapSequenceCapture(
                onUpdate: { [weak self] action in
                    self?.doubleTapAction = action
                },
                onFinalize: { [weak self] action in
                    self?.doubleTapAction = action
                },
                onStop: { [weak self] in
                    self?.isRecordingDoubleTap = false
                }
            )
        }
    }

    func toggleComboOutputRecording() {
        if isRecordingComboOutput {
            isRecordingComboOutput = false
            stopSimpleKeyCapture()
        } else {
            // Stop any other recording
            stopRecording()
            isRecordingComboOutput = true
            startSimpleKeyCapture { [weak self] keyName in
                self?.comboOutput = keyName
                self?.isRecordingComboOutput = false
            }
        }
    }
}
