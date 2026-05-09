import AppKit
import KeyPathCore
import KeyPathInstallationWizard
import KeyPathWizardCore
import SwiftUI

/// The main live keyboard overlay view.
/// Shows a borderless floating keyboard that highlights keys as they are pressed.
struct LiveKeyboardOverlayView: View {
    var viewModel: KeyboardVisualizationViewModel
    var uiState: LiveKeyboardOverlayUIState
    let inspectorWidth: CGFloat
    let isMapperAvailable: Bool
    let kanataViewModel: KanataViewModel?
    /// Callback when a key is clicked (not dragged) - selects key in drawer mapper when visible
    var onKeyClick: ((PhysicalKey, LayerKeyInfo?) -> Void)?
    /// Callback when the overlay close button is pressed
    var onClose: (() -> Void)?
    /// Callback when the inspector button is pressed
    var onToggleInspector: (() -> Void)?
    /// Callback when keymap selection changes (keymapId, includePunctuation)
    var onKeymapChanged: ((String, Bool) -> Void)?
    /// Callback when health indicator is tapped (to launch wizard)
    var onHealthIndicatorTap: (() -> Void)?

    // MARK: - Environment

    @Environment(\.services) var services
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var keymapIncludePunctuationStore: String = "{}"

    // MARK: - Inspector State

    @State var escKeyLeftInset: CGFloat = 0
    @State private var keyboardWidth: CGFloat = 0
    /// Cached "is the KindaVim Mode Display pack installed?" flag.
    /// Refreshed on `.installedPacksChanged` so the keyboard render path
    /// doesn't have to await the tracker actor.
    @State var kindaVimPackInstalled = false
    @State private var inspectorSectionRaw: String = InspectorSection.mapper.rawValue
    @AppStorage("inspectorSettingsSection") private var settingsSectionRaw: String = InspectorSection.keyboard.rawValue
    var inspectorSection: InspectorSection {
        get { InspectorSection(rawValue: inspectorSectionRaw) ?? .mapper }
        nonmutating set { inspectorSectionRaw = newValue.rawValue }
    }

    private var settingsSection: InspectorSection {
        get {
            let section = InspectorSection(rawValue: settingsSectionRaw) ?? .keycaps
            return section.isSettingsShelf ? section : .keycaps
        }
        nonmutating set { settingsSectionRaw = newValue.rawValue }
    }

    // MARK: - Rule & Custom Rules State

    /// Whether custom rules exist (for showing Custom Rules tab)
    @State var hasCustomRules = false
    /// Cached global custom rules for Custom Rules tab content
    @State var cachedCustomRules: [CustomRule] = []
    /// Cached app keymaps for Custom Rules tab content
    @State var appKeymaps: [AppKeymap] = []
    /// Whether to show reset all rules confirmation dialog
    @State var showResetAllRulesConfirmation = false
    /// Pending app rule deletion (for confirmation dialog)
    @State var pendingDeleteRule: (keymap: AppKeymap, override: AppKeyOverride)?
    /// Error message for failed app rule deletion
    @State var appRuleDeleteError: String?

    // MARK: - Input & Settings State

    /// Japanese input mode detector for showing mode indicator
    var inputSourceDetector = InputSourceDetector.shared
    /// Whether the settings shelf is active (gear mode)
    @State var isSettingsShelfActive = false

    // MARK: - Drag State

    @State var keyboardDragInitialFrame: NSRect = .zero
    @State var keyboardDragInitialMouseLocation: NSPoint = .zero
    @State var isKeyboardDragging = false
    @State var isHeaderDragging = false

    // MARK: - Hover State

    /// Whether the mouse is currently hovering over the overlay (for focus indicator)
    @State var isOverlayHovered = false
    @State var isHoveringHeaderButton = false

    // MARK: - Launcher Welcome State

    @AppStorage("launcherWelcomeSeenForBuild") var launcherWelcomeSeenForBuild: String = ""
    @State var pendingLauncherConfig: LauncherGridConfig?

    // MARK: - Runtime Stopped Alert (Overlay)

    @State var showingRuntimeStoppedAlert = false
    @State private var lastRuntimeIssuePresent = false
    @State private var hasSeenHealthyRuntime = false
    @State private var overlayLaunchTime = Date()
    @State private var toastManager = WizardToastManager()
    @State private var lastReloadFailureToastAt: Date?
    @State private var autoDetectToastHeight: CGFloat = 88
    var autoDetectController: AutoDetectKeyboardController {
        .shared
    }

    @State var showingValidationFailureModal = false
    @State var validationFailureErrors: [String] = []

    // MARK: - Computed Properties

    /// The currently selected physical keyboard layout
    var activeLayout: PhysicalLayout {
        PhysicalLayout.find(id: selectedLayoutId) ?? .macBookUS
    }

    /// The currently selected logical keymap for labeling
    var activeKeymap: LogicalKeymap {
        .resolve(id: selectedKeymapId)
    }

    /// Whether to apply number row + outer punctuation mappings
    var includeKeymapPunctuation: Bool {
        KeymapPreferences.includePunctuation(
            for: selectedKeymapId,
            store: keymapIncludePunctuationStore
        )
    }

    private var settingsShelfAnimation: Animation {
        .spring(response: 0.5, dampingFraction: 0.72, blendDuration: 0.12)
    }

    private var autoDetectToastGap: CGFloat { 10 }

    private var autoDetectToastOffsetY: CGFloat {
        guard let window = findOverlayWindow(),
              let screen = window.screen ?? NSScreen.main
        else {
            return -(autoDetectToastHeight + autoDetectToastGap)
        }

        let visibleFrame = screen.visibleFrame
        let roomAbove = visibleFrame.maxY - window.frame.maxY
        let requiredHeight = autoDetectToastHeight + autoDetectToastGap

        if roomAbove >= requiredHeight {
            return -requiredHeight
        }

        return window.frame.height + autoDetectToastGap
    }

    // MARK: - Actions

    func selectInspectorSection(_ section: InspectorSection) {
        if section.isSettingsShelf {
            settingsSection = section
            inspectorSection = section
            if !isSettingsShelfActive {
                isSettingsShelfActive = true
            }
        } else {
            inspectorSection = section
            if isSettingsShelfActive {
                isSettingsShelfActive = false
            }
        }
    }

    func toggleSettingsShelf() {
        let animation: Animation? = reduceMotion ? nil : settingsShelfAnimation
        withAnimation(animation) {
            if isSettingsShelfActive {
                isSettingsShelfActive = false
                inspectorSection = .mapper
            } else {
                isSettingsShelfActive = true
                inspectorSection = settingsSection
            }
        }
    }

    private func handleRuntimeIssueChange(_ issues: [WizardIssue]) {
        let runtimeIssue = issues.first { issue in
            if case .component(.keyPathRuntime) = issue.identifier {
                return true
            }
            return false
        }
        let hasRuntimeIssue = runtimeIssue != nil

        if !hasRuntimeIssue {
            if let state = MainAppStateController.shared.validationState, state != .checking {
                hasSeenHealthyRuntime = true
            }
        }

        // Grace period: don't show alert within 10s of launch (service may bounce during startup/deploy)
        let timeSinceLaunch = Date().timeIntervalSince(overlayLaunchTime)
        let wizardOpen = WizardWindowController.shared.isVisible

        if hasRuntimeIssue,
           !lastRuntimeIssuePresent,
           hasSeenHealthyRuntime,
           !wizardOpen,
           timeSinceLaunch > 10
        {
            showingRuntimeStoppedAlert = true
        }

        lastRuntimeIssuePresent = hasRuntimeIssue
    }

    private func openSystemStatusSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        NotificationCenter.default.post(name: .openSettingsSystemStatus, object: nil)
    }

    /// Refresh the cached "kindaVim pack installed" flag from the
    /// tracker. Called on appear and on `.installedPacksChanged`. The
    /// flag drives the overlay vim-hint layer's render gate.
    private func refreshKindaVimPackInstalled() async {
        let installed = await InstalledPackTracker.shared
            .isInstalled(packID: PackRegistry.kindaVim.id)
        await MainActor.run { kindaVimPackInstalled = installed }
    }

    private func copyValidationErrorsToClipboard() {
        let text = validationFailureErrors.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Body

    var body: some View {
        let cornerRadius: CGFloat = 10
        let fadeAmount: CGFloat = viewModel.fadeAmount
        let headerHeight = OverlayLayoutMetrics.headerHeight
        let keyboardPadding = OverlayLayoutMetrics.keyboardPadding
        let baseKeyboardTrailingPadding = OverlayLayoutMetrics.keyboardTrailingPadding
        let headerBottomSpacing = OverlayLayoutMetrics.headerBottomSpacing
        let outerHorizontalPadding = OverlayLayoutMetrics.outerHorizontalPadding
        let inspectorReveal = uiState.inspectorReveal
        let inspectorVisible = uiState.isInspectorAnimating || inspectorReveal > 0
        let allowKeyboardDrag = !uiState.isInspectorOpen
            && !uiState.isInspectorAnimating
            && inspectorReveal <= 0.001
        let inspectorDebugEnabled = UserDefaults.standard.bool(forKey: "OverlayInspectorDebug")
        let isOverlayDragging = isKeyboardDragging || isHeaderDragging
        let trailingOuterPadding = inspectorVisible ? 0 : outerHorizontalPadding
        let keyboardAspectRatio = activeLayout.totalWidth / activeLayout.totalHeight
        let inspectorSeamWidth = OverlayLayoutMetrics.inspectorSeamWidth
        let inspectorLeadingGap = inspectorVisible ? baseKeyboardTrailingPadding : 0
        let keyboardTrailingPadding = inspectorVisible ? 0 : baseKeyboardTrailingPadding
        let inspectorPanelWidth = inspectorWidth + inspectorSeamWidth
        let inspectorTotalWidth = inspectorPanelWidth + inspectorLeadingGap
        let inspectorChrome = inspectorVisible ? inspectorTotalWidth : 0
        let verticalChrome = OverlayLayoutMetrics.verticalChrome
        let shouldFreezeKeyboard = uiState.isInspectorAnimating || inspectorVisible || uiState.isInspectorOpen
        let fixedKeyboardWidth: CGFloat? = keyboardWidth > 0 ? keyboardWidth : nil
        let fixedKeyboardHeight: CGFloat? = fixedKeyboardWidth.map { $0 / keyboardAspectRatio }

        overlayContent(
            fadeAmount: fadeAmount,
            headerHeight: headerHeight,
            inspectorVisible: inspectorVisible,
            inspectorReveal: inspectorReveal,
            inspectorPanelWidth: inspectorPanelWidth,
            inspectorTotalWidth: inspectorTotalWidth,
            inspectorLeadingGap: inspectorLeadingGap,
            inspectorDebugEnabled: inspectorDebugEnabled,
            fixedKeyboardWidth: fixedKeyboardWidth,
            fixedKeyboardHeight: fixedKeyboardHeight,
            headerBottomSpacing: headerBottomSpacing,
            keyboardPadding: keyboardPadding,
            keyboardTrailingPadding: keyboardTrailingPadding,
            allowKeyboardDrag: allowKeyboardDrag
        )
        .overlayLayoutHandlers(
            keyboardPadding: keyboardPadding,
            keyboardTrailingPadding: keyboardTrailingPadding,
            inspectorChrome: inspectorChrome,
            shouldFreezeKeyboard: shouldFreezeKeyboard,
            keyboardAspectRatio: keyboardAspectRatio,
            verticalChrome: verticalChrome,
            inspectorVisible: inspectorVisible,
            keyboardWidth: $keyboardWidth,
            uiState: uiState,
            viewModel: viewModel,
            activeLayout: activeLayout,
            selectedLayoutId: selectedLayoutId,
            isMapperAvailable: isMapperAvailable,
            hasCustomRules: hasCustomRules,
            inspectorSection: inspectorSection,
            setInspectorSection: { inspectorSection = $0 },
            setSettingsSection: { settingsSection = $0 },
            isSettingsShelfActive: isSettingsShelfActive,
            setIsSettingsShelfActive: { isSettingsShelfActive = $0 },
            checkLauncherWelcome: { checkLauncherWelcome() }
        )
        .modifier(OverlayNotificationsModifier(
            onAppearAction: {
                uiState.keyboardAspectRatio = keyboardAspectRatio
                inputSourceDetector.startMonitoring()
                autoDetectController.startObserving()
                if !isMapperAvailable, inspectorSection == .mapper {
                    inspectorSection = hasCustomRules ? .customRules : .launchers
                }
                if inspectorSection.isSettingsShelf {
                    settingsSection = inspectorSection
                    isSettingsShelfActive = false
                    inspectorSection = .mapper
                }
                if viewModel.layout.id != activeLayout.id {
                    viewModel.setLayout(activeLayout)
                }
                loadCustomRulesState()
                Task { await refreshKindaVimPackInstalled() }
            },
            onDisappearAction: {
                inputSourceDetector.stopMonitoring()
                autoDetectController.stopObserving()
            },
            onLoadCustomRulesState: { loadCustomRulesState() },
            onServiceIssueChange: { handleRuntimeIssueChange($0) },
            onConfigValidationFailed: { notification in
                let errors = notification.userInfo?["errors"] as? [String] ?? []
                guard !errors.isEmpty else { return }
                validationFailureErrors = errors
                showingValidationFailureModal = true
            },
            onConfigReloadFailed: { notification in
                let now = Date()
                if let last = lastReloadFailureToastAt, now.timeIntervalSince(last) < 10 {
                    return
                }
                lastReloadFailureToastAt = now
                let message = (notification.userInfo?["message"] as? String) ?? "Config reload failed"
                toastManager.showError("Reload delayed: \(message)")
                SoundManager.shared.playErrorSound()
            },
            onConfigReloadRecovered: {
                guard lastReloadFailureToastAt != nil else { return }
                lastReloadFailureToastAt = nil
                toastManager.showSuccess("Reload recovered")
                SoundManager.shared.playGlassSound()
            },
            onSwitchToAppRulesTab: {
                loadCustomRulesState()
                isSettingsShelfActive = false
                if hasCustomRules {
                    inspectorSection = .customRules
                }
            },
            onSwitchToMapperTab: { notification in
                isSettingsShelfActive = false
                inspectorSection = .mapper
                if let userInfo = notification.userInfo,
                   let inputKey = userInfo["inputKey"] as? String,
                   let outputKey = userInfo["outputKey"] as? String
                {
                    var mapperUserInfo: [String: Any] = [
                        "inputKey": inputKey,
                        "outputKey": outputKey,
                        "keyCode": UInt16(0)
                    ]
                    if let shiftedOutputKey = userInfo["shiftedOutputKey"] as? String {
                        mapperUserInfo["shiftedOutputKey"] = shiftedOutputKey
                    }
                    if let appBundleId = userInfo["appBundleId"] as? String,
                       let appDisplayName = userInfo["appDisplayName"] as? String
                    {
                        mapperUserInfo["appBundleId"] = appBundleId
                        mapperUserInfo["appDisplayName"] = appDisplayName
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        NotificationCenter.default.post(
                            name: .mapperDrawerKeySelected,
                            object: nil,
                            userInfo: mapperUserInfo
                        )
                    }
                }
            },
            onMapperKeySelected: { notification in
                if inspectorSection == .customRules {
                    inspectorSection = .mapper
                    if let userInfo = notification.userInfo {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            NotificationCenter.default.post(
                                name: .mapperDrawerKeySelected,
                                object: nil,
                                userInfo: userInfo
                            )
                        }
                    }
                }
            }
        ))
        .onReceive(NotificationCenter.default.publisher(for: .installedPacksChanged)) { _ in
            Task { await refreshKindaVimPackInstalled() }
        }
        .background(
            glassBackground(
                cornerRadius: cornerRadius,
                fadeAmount: fadeAmount,
                isHovered: isOverlayHovered,
                isDragging: isOverlayDragging
            )
        )
        .overlayAppearance(
            cornerRadius: cornerRadius,
            outerHorizontalPadding: outerHorizontalPadding,
            trailingOuterPadding: trailingOuterPadding,
            deepFadeAmount: viewModel.deepFadeAmount,
            reduceMotion: reduceMotion,
            onMouseMove: { viewModel.noteInteraction() }
        )
        .environment(viewModel)
        .overlayCursorTracking(
            isOverlayHovered: $isOverlayHovered,
            isKeyboardDragging: isKeyboardDragging,
            isHeaderDragging: isHeaderDragging,
            isHoveringHeaderButton: isHoveringHeaderButton,
            inspectorReveal: uiState.inspectorReveal,
            isInspectorOpen: uiState.isInspectorOpen,
            isInspectorAnimating: uiState.isInspectorAnimating,
            allowKeyboardDrag: allowKeyboardDrag,
            noteInteraction: { viewModel.noteInteraction() },
            refreshCursor: { refreshOverlayCursor(allowDragCursor: allowKeyboardDrag) }
        )
        .modifier(OverlayDialogsModifier(
            pendingDeleteRule: $pendingDeleteRule,
            appRuleDeleteError: $appRuleDeleteError,
            showingRuntimeStoppedAlert: $showingRuntimeStoppedAlert,
            showingValidationFailureModal: $showingValidationFailureModal,
            validationFailureErrors: $validationFailureErrors,
            showResetAllRulesConfirmation: $showResetAllRulesConfirmation,
            onDeleteAppRule: { keymap, override in
                deleteAppRule(keymap: keymap, override: override)
            },
            onRestartRuntime: {
                Task { @MainActor in
                    guard let kanataViewModel else { return }
                    _ = await kanataViewModel.restartKanata(
                        reason: "Service stopped alert (overlay)"
                    )
                }
            },
            onCopyValidationErrors: { copyValidationErrorsToClipboard() },
            onOpenConfig: {
                guard let kanataViewModel else { return }
                kanataViewModel.openFileInZed(kanataViewModel.configPath)
                showingValidationFailureModal = false
            },
            onOpenDiagnostics: {
                openSystemStatusSettings()
                showingValidationFailureModal = false
            },
            onResetAllRules: { resetAllCustomRules() },
            configPath: kanataViewModel?.configPath ?? ""
        ))
        .overlay(alignment: .top) {
            if autoDetectController.showingToast {
                AutoDetectToastView(
                    keyboardName: autoDetectController.toastKeyboardName,
                    mode: autoDetectController.toastMode,
                    confidence: autoDetectController.toastConfidence,
                    errorMessage: autoDetectController.toastErrorMessage,
                    onAccept: { autoDetectController.acceptDetection() },
                    onDismiss: { autoDetectController.dismissToast() }
                )
                .padding(.horizontal, 16)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                autoDetectToastHeight = proxy.size.height
                            }
                            .onChange(of: proxy.size.height) { _, newHeight in
                                autoDetectToastHeight = newHeight
                            }
                    }
                }
                .offset(y: autoDetectToastOffsetY)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { autoDetectController.isKeyboardSearchPresented },
                set: { isPresented in
                    if !isPresented {
                        autoDetectController.dismissKeyboardSearch()
                    }
                }
            )
        ) {
            QMKKeyboardSearchView(
                selectedLayoutId: $selectedLayoutId,
                initialQuery: autoDetectController.keyboardSearchQuery,
                onImportComplete: {
                    autoDetectController.rememberCurrentLayoutSelection(layoutId: selectedLayoutId)
                }
            )
        }
        .withToasts(toastManager)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keyboard-overlay")
        .accessibilityLabel("KeyPath keyboard overlay")
        .onChange(of: selectedLayoutId) { _, newLayoutId in
            autoDetectController.overlayDisplayContextDidChange(
                layoutId: newLayoutId,
                keymapId: selectedKeymapId,
                includePunctuationStore: keymapIncludePunctuationStore
            )
        }
        .onChange(of: selectedKeymapId) { _, newKeymapId in
            autoDetectController.overlayDisplayContextDidChange(
                layoutId: selectedLayoutId,
                keymapId: newKeymapId,
                includePunctuationStore: keymapIncludePunctuationStore
            )
        }
        .onChange(of: keymapIncludePunctuationStore) { _, newStore in
            autoDetectController.overlayDisplayContextDidChange(
                layoutId: selectedLayoutId,
                keymapId: selectedKeymapId,
                includePunctuationStore: newStore
            )
        }
        .onChange(of: autoDetectController.activeKeyboardID) { oldKeyboardID, newKeyboardID in
            Task { @MainActor in
                if let restoredContext = await autoDetectController.activeKeyboardDidChange(
                    from: oldKeyboardID,
                    to: newKeyboardID,
                    currentLayoutId: selectedLayoutId,
                    currentKeymapId: selectedKeymapId,
                    includePunctuationStore: keymapIncludePunctuationStore
                ) {
                    if selectedLayoutId != restoredContext.layoutId {
                        selectedLayoutId = restoredContext.layoutId
                    }
                    if selectedKeymapId != restoredContext.keymapId {
                        selectedKeymapId = restoredContext.keymapId
                    }
                    if keymapIncludePunctuationStore != restoredContext.includePunctuationStore {
                        keymapIncludePunctuationStore = restoredContext.includePunctuationStore
                    }
                }
            }
        }
    }

}
