import AppKit
import KeyPathCore
import SwiftUI

// MapperActionTypes (AppLaunchInfo, AppConditionInfo, SystemActionInfo)
// are defined in MapperActionTypes.swift

// MARK: - Mapper View Model

@Observable
@MainActor
class MapperViewModel {
    var inputLabel: String = "A"
    var outputLabel: String = "A"
    var shiftedOutputLabel: String?
    /// Whether the current shifted output is the system default (not a custom override)
    var isShiftedOutputDefault = false
    var isRecordingInput = false
    var isRecordingOutput = false
    var isRecordingShiftedOutput = false
    var isSaving = false
    var statusMessage: String?
    var statusIsError = false
    private var statusDismissTask: Task<Void, Never>?
    var currentLayer: String = "base"
    var availableLayers: [String] = ["base", "nav"]
    /// Selected app for launch action (nil = normal key output)
    var selectedApp: AppLaunchInfo?
    /// Selected system action (nil = normal key output)
    var selectedSystemAction: SystemActionInfo?
    /// Selected URL for web URL mapping (nil = normal key output)
    var selectedURL: String? {
        didSet {
            if selectedURL != oldValue {
                selectedURLFavicon = nil
            }
        }
    }

    /// Favicon for the selected URL
    var selectedURLFavicon: NSImage?
    /// Whether the URL input dialog is visible
    var showingURLDialog = false
    /// Text input for URL dialog
    var urlInputText = ""
    /// Selected folder path for folder-open mapping (nil = normal key output)
    var selectedFolder: (path: String, name: String?)?
    /// Selected script path for script-run mapping (nil = normal key output)
    var selectedScript: (path: String, name: String?)?

    // MARK: - Output-Type Picker (Overlay) Navigation State

    /// Which page the overlay output-type picker is showing.
    ///
    /// The picker is an iPhone-style drill-down — the root list and each
    /// sub-list (System Action / Launch App / Go to Layer) are separate pages
    /// that slide over one another inside a *stable* popover frame. This
    /// deliberately replaced inline expansion: growing the popover's height
    /// forced the hoisted window-anchored layer to re-measure and reposition on
    /// every toggle, which fought SwiftUI's preference/position machinery and
    /// left the expandable rows unresponsive. Swapping pages in a fixed frame
    /// avoids all of that.
    ///
    /// It lives on the view model (not `@State` on the view) because the picker
    /// is rendered in that detached hoisted layer; `@State` mutated from there
    /// does not propagate back, whereas this shared `@Observable` reference does.
    enum OutputPickerPage: Equatable {
        case root
        case systemActions
        case launchApps
        case layers
    }

    var outputPickerPage: OutputPickerPage = .root
    /// Selected layer name for "Go to Layer" output (nil = not a layer output).
    var selectedLayerOutput: String?
    /// Filter text for the Launch App sub-page's known-apps list. Lives here
    /// (not `@State` on the view) because the picker popover is hoisted; a
    /// `TextField` bound to view `@State` from that detached layer wouldn't
    /// propagate. Cleared each time the picker opens.
    var launchAppSearchText: String = ""

    /// Key code of the captured input (for overlay-style rendering)
    /// Default to 0 (A key) so the default state shows the A key selected
    var inputKeyCode: UInt16? = 0
    /// Apps that have a mapping for the currently selected input key
    var appsWithCurrentKeyMapping: [AppKeymap] = []

    // MARK: - Device Condition

    /// Selected device condition (nil = all keyboards)
    var selectedDeviceCondition: DeviceConditionInfo?

    // MARK: - App Condition (Delegated to AppConditionManager)

    /// Manager for app condition (precondition) selection
    var appConditionManager = AppConditionManager()

    /// Legacy accessor for selectedAppCondition
    var selectedAppCondition: AppConditionInfo? {
        get { appConditionManager.selectedAppCondition }
        set {
            appConditionManager.selectedAppCondition = newValue
            if newValue != nil {
                clearShiftedOutput()
            }
        }
    }

    // MARK: - Advanced Behavior (Delegated to AdvancedBehaviorManager)

    /// Manager for advanced key behaviors (hold, tap-dance, timing)
    /// Views should access advanced behavior properties through this manager.
    var advancedBehavior = AdvancedBehaviorManager()

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
    @ObservationIgnored var inputSequence: KeySequence? = MapperViewModel.defaultAKeySequence
    @ObservationIgnored var outputSequence: KeySequence? = MapperViewModel.defaultAKeySequence
    @ObservationIgnored var shiftedOutputSequence: KeySequence?
    @ObservationIgnored var keyboardCapture: KeyboardCapture?
    @ObservationIgnored var simpleKeyCaptureMonitor: Any?
    @ObservationIgnored var simpleKeyCaptureToken: UUID?
    @ObservationIgnored var multiTapFinalizeTimer: Timer?
    @ObservationIgnored var multiTapPendingSequence: KeySequence?
    @ObservationIgnored var multiTapUpdateHandler: ((String) -> Void)?
    @ObservationIgnored var multiTapFinalizeHandler: ((String) -> Void)?
    @ObservationIgnored var multiTapStopHandler: (() -> Void)?
    @ObservationIgnored var kanataManager: RuntimeCoordinator?
    var rulesManager: RuleCollectionsManager? {
        kanataManager?.rulesManager
    }

    @ObservationIgnored var finalizeTimer: Timer?
    /// ID of the last saved custom rule (for clearing/deleting)
    @ObservationIgnored var lastSavedRuleID: UUID?
    /// Original key context from overlay click (for reset after clear)
    @ObservationIgnored var originalInputKey: String?
    @ObservationIgnored var originalOutputKey: String?
    @ObservationIgnored var originalShiftedOutputKey: String?
    @ObservationIgnored var originalAppIdentifier: String?
    @ObservationIgnored var originalSystemActionIdentifier: String?
    @ObservationIgnored var originalURL: String?
    /// Original layer from overlay click
    @ObservationIgnored var originalLayer: String?

    /// State saved before starting output recording (for restore on cancel)
    @ObservationIgnored var savedOutputLabel: String?
    @ObservationIgnored var savedOutputSequence: KeySequence?
    @ObservationIgnored var savedShiftedOutputLabel: String?
    @ObservationIgnored var savedShiftedOutputSequence: KeySequence?
    @ObservationIgnored var savedSelectedApp: AppLaunchInfo?
    @ObservationIgnored var savedSelectedSystemAction: SystemActionInfo?
    @ObservationIgnored var savedMacroBehavior: MacroBehavior?

    /// Delay before finalizing a sequence capture (allows for multi-key sequences)
    @ObservationIgnored let sequenceFinalizeDelay: TimeInterval = 0.8

    /// Show a success status message that auto-dismisses after a delay
    /// Show a success status message that auto-dismisses after a delay
    func showTransientStatus(_ message: String, duration: Duration = .seconds(2)) {
        statusDismissTask?.cancel()
        statusMessage = message
        statusIsError = false
        statusDismissTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                statusMessage = nil
            }
        }
    }

    func clearShiftedOutput() {
        shiftedOutputLabel = nil
        shiftedOutputSequence = nil
        originalShiftedOutputKey = nil
        isRecordingShiftedOutput = false
        isShiftedOutputDefault = false
    }

    func currentShiftedOutputKanataString() -> String? {
        // Don't save system default shift as a custom rule
        guard !isShiftedOutputDefault else { return nil }
        guard let shiftedOutputSequence else { return nil }
        let kanata = convertSequenceToKanataFormat(shiftedOutputSequence)
        return kanata.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : kanata
    }

    func toggleInputRecording() {
        if isRecordingInput {
            stopRecording()
        } else {
            // Stop output recording if active
            if isRecordingOutput || isRecordingShiftedOutput {
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
            if isRecordingInput || isRecordingShiftedOutput {
                stopRecording()
            }
            startOutputRecording()
        }
    }

    func toggleShiftedOutputRecording() {
        if isRecordingShiftedOutput {
            stopRecording()
        } else {
            if isRecordingInput || isRecordingOutput {
                stopRecording()
            }
            startShiftedOutputRecording()
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
