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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var keymapIncludePunctuationStore: String = "{}"

    // MARK: - Inspector State

    @State private var escKeyLeftInset: CGFloat = 0
    @State private var keyboardWidth: CGFloat = 0
    /// Cached "is the KindaVim Mode Display pack installed?" flag.
    /// Refreshed on `.installedPacksChanged` so the keyboard render path
    /// doesn't have to await the tracker actor.
    @State private var kindaVimPackInstalled = false
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
    @State private var isSettingsShelfActive = false

    // MARK: - Drag State

    @State private var keyboardDragInitialFrame: NSRect = .zero
    @State private var keyboardDragInitialMouseLocation: NSPoint = .zero
    @State private var isKeyboardDragging = false
    @State private var isHeaderDragging = false

    // MARK: - Hover State

    /// Whether the mouse is currently hovering over the overlay (for focus indicator)
    @State private var isOverlayHovered = false
    /// Whether the mouse is hovering over a clickable header button (drawer/hide)
    @State private var isHoveringHeaderButton = false

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
    private var autoDetectController: AutoDetectKeyboardController {
        .shared
    }

    @State var showingValidationFailureModal = false
    @State var validationFailureErrors: [String] = []

    // MARK: - Computed Properties

    /// The currently selected physical keyboard layout
    private var activeLayout: PhysicalLayout {
        PhysicalLayout.find(id: selectedLayoutId) ?? .macBookUS
    }

    /// The currently selected logical keymap for labeling
    private var activeKeymap: LogicalKeymap {
        .resolve(id: selectedKeymapId)
    }

    /// Whether to apply number row + outer punctuation mappings
    private var includeKeymapPunctuation: Bool {
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

    private func selectInspectorSection(_ section: InspectorSection) {
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

    private func toggleSettingsShelf() {
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

    // MARK: - Overlay Content

    private func overlayContent(
        fadeAmount: CGFloat,
        headerHeight: CGFloat,
        inspectorVisible: Bool,
        inspectorReveal: CGFloat,
        inspectorPanelWidth: CGFloat,
        inspectorTotalWidth: CGFloat,
        inspectorLeadingGap: CGFloat,
        inspectorDebugEnabled: Bool,
        fixedKeyboardWidth: CGFloat?,
        fixedKeyboardHeight: CGFloat?,
        headerBottomSpacing: CGFloat,
        keyboardPadding: CGFloat,
        keyboardTrailingPadding: CGFloat,
        allowKeyboardDrag: Bool
    ) -> some View {
        VStack(spacing: 0) {
            OverlayDragHeader(
                isDark: isDark,
                fadeAmount: fadeAmount,
                height: headerHeight,
                inspectorWidth: inspectorTotalWidth,
                reduceTransparency: reduceTransparency,
                isInspectorOpen: uiState.isInspectorOpen,
                isDragging: $isHeaderDragging,
                isHoveringButton: $isHoveringHeaderButton,
                inputModeIndicator: inputSourceDetector.modeIndicator,
                currentLayerName: viewModel.currentLayerName,
                isLauncherMode: viewModel.isLauncherModeActive || (uiState.isInspectorOpen && inspectorSection == .launchers),
                isKanataConnected: viewModel.isKanataConnected,
                healthIndicatorState: uiState.healthIndicatorState,
                drawerButtonHighlighted: uiState.drawerButtonHighlighted,
                layoutHasDrawerButtons: activeLayout.hasDrawerButtons,
                onClose: { onClose?() },
                onToggleInspector: { onToggleInspector?() },
                onHealthTap: { onHealthIndicatorTap?() },
                connectedKeyboards: autoDetectController.connectedKeyboards,
                activeKeyboardID: autoDetectController.activeKeyboardID,
                onKeyboardSelected: { keyboardID in
                    autoDetectController.selectKeyboard(keyboardID)
                },
                onLayerSelected: { layerName in
                    Task {
                        _ = await kanataViewModel?.changeLayer(layerName)
                    }
                },
                onCreateLayer: { layerName in
                    Task {
                        await kanataViewModel?.underlyingManager.rulesManager.createLayer(layerName)
                        _ = await kanataViewModel?.changeLayer(layerName)
                    }
                },
                onDeleteLayer: { layerName in
                    Task {
                        if kanataViewModel?.currentLayerName.lowercased() == layerName.lowercased() {
                            _ = await kanataViewModel?.changeLayer("base")
                        }
                        await kanataViewModel?.underlyingManager.rulesManager.removeLayer(layerName)
                    }
                }
            )
            .frame(maxWidth: .infinity)

            overlayMainContent(
                fadeAmount: fadeAmount,
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
                allowKeyboardDrag: allowKeyboardDrag,
                inspectorSection: inspectorSection
            )
        }
    }

    // MARK: - Main Content

    private func overlayMainContent(
        fadeAmount: CGFloat,
        inspectorVisible: Bool,
        inspectorReveal: CGFloat,
        inspectorPanelWidth: CGFloat,
        inspectorTotalWidth: CGFloat,
        inspectorLeadingGap: CGFloat,
        inspectorDebugEnabled: Bool,
        fixedKeyboardWidth: CGFloat?,
        fixedKeyboardHeight: CGFloat?,
        headerBottomSpacing: CGFloat,
        keyboardPadding: CGFloat,
        keyboardTrailingPadding: CGFloat,
        allowKeyboardDrag: Bool,
        inspectorSection: InspectorSection
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // 1. Inspector FIRST = renders at the back
            if inspectorVisible {
                let reveal = max(0, min(1, inspectorReveal))
                let slideOffset = -(1 - reveal) * inspectorPanelWidth
                let inspectorOpacity: CGFloat = 1
                let inspectorContent = makeInspectorContent(
                    fadeAmount: fadeAmount,
                    inspectorTotalWidth: inspectorTotalWidth,
                    inspectorReveal: reveal,
                    inspectorLeadingGap: inspectorLeadingGap,
                    healthIndicatorState: uiState.healthIndicatorState,
                    onHealthTap: { onHealthIndicatorTap?() },
                    onKeySelected: { keyCode in
                        viewModel.selectedKeyCode = keyCode
                    },
                    onRuleHover: { inputKey in
                        if let key = inputKey {
                            viewModel.hoveredRuleKeyCode = LogicalKeymap.keyCode(forQwertyLabel: key)
                            viewModel.selectedKeyCode = nil
                        } else {
                            viewModel.hoveredRuleKeyCode = nil
                        }
                    }
                )

                InspectorMaskedHost(
                    content: inspectorContent,
                    reveal: reveal,
                    totalWidth: inspectorTotalWidth,
                    leadingGap: inspectorLeadingGap,
                    slideOffset: slideOffset,
                    opacity: inspectorOpacity,
                    debugEnabled: inspectorDebugEnabled
                )
                .frame(width: inspectorTotalWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
            }

            // 2. Opaque blocker SECOND = blocks inspector behind keyboard area
            if inspectorVisible, let kbWidth = fixedKeyboardWidth, let kbHeight = fixedKeyboardHeight {
                Rectangle()
                    .fill(Color(white: isDark ? 0.1 : 0.92))
                    .frame(width: kbWidth, height: kbHeight)
                    .padding(.top, headerBottomSpacing)
                    .padding(.leading, keyboardPadding)
            }

            // 3. Keyboard THIRD = renders on top with transparent glass
            HStack(alignment: .top, spacing: 0) {
                let keyboardView = OverlayKeyboardView(
                    layout: activeLayout,
                    keymap: activeKeymap,
                    includeKeymapPunctuation: includeKeymapPunctuation,
                    pressedKeyCodes: viewModel.pressedKeyCodes,
                    isDarkMode: isDark,
                    fadeAmount: fadeAmount,
                    keyFadeAmounts: viewModel.keyFadeAmounts,
                    currentLayerName: viewModel.currentLayerName,
                    isLoadingLayerMap: viewModel.isLoadingLayerMap,
                    layerKeyMap: viewModel.layerKeyMap,
                    effectivePressedKeyCodes: viewModel.effectivePressedKeyCodes,
                    emphasizedKeyCodes: viewModel.emphasizedKeyCodes,
                    oneShotKeyCodes: viewModel.oneShotHighlightedKeyCodes,
                    holdLabels: viewModel.holdLabels,
                    tapHoldIdleLabels: viewModel.tapHoldIdleLabels,
                    holdReleaseFadeKeyCodes: viewModel.holdReleaseFadeKeyCodes,
                    customIcons: viewModel.customIcons,
                    onKeyClick: onKeyClick,
                    selectedKeyCode: viewModel.selectedKeyCode,
                    hoveredRuleKeyCode: viewModel.hoveredRuleKeyCode,
                    vimHintsActive: kindaVimPackInstalled,
                    isLauncherMode: viewModel.isLauncherModeActive || (uiState.isInspectorOpen && inspectorSection == .launchers),
                    launcherMappings: viewModel.launcherMappings,
                    isInspectorVisible: inspectorVisible
                )
                .environment(viewModel)
                .frame(
                    width: fixedKeyboardWidth,
                    height: fixedKeyboardHeight,
                    alignment: .leading
                )
                .onPreferenceChange(EscKeyLeftInsetPreferenceKey.self) { newValue in
                    escKeyLeftInset = newValue
                }
                .animation(nil, value: fixedKeyboardWidth)

                if allowKeyboardDrag {
                    keyboardView
                        .contentShape(Rectangle())
                        // Use simultaneousGesture (not highPriority) so the Touch ID keycap's
                        // TapGesture can fire alongside this drag gesture. Non-TouchID keycaps
                        // already have .allowsHitTesting(false) when the drawer is closed,
                        // so there's no risk of accidental key clicks during drag.
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                                .onChanged { _ in
                                    if !isKeyboardDragging, let window = findOverlayWindow() {
                                        keyboardDragInitialFrame = window.frame
                                        keyboardDragInitialMouseLocation = NSEvent.mouseLocation
                                        viewModel.noteInteraction()
                                        isKeyboardDragging = true
                                    }
                                    updateOverlayCursor(
                                        hovering: isOverlayHovered,
                                        isDragging: true,
                                        allowDragCursor: allowKeyboardDrag
                                    )
                                    let currentMouse = NSEvent.mouseLocation
                                    let deltaX = currentMouse.x - keyboardDragInitialMouseLocation.x
                                    let deltaY = currentMouse.y - keyboardDragInitialMouseLocation.y
                                    moveKeyboardWindow(deltaX: deltaX, deltaY: deltaY)
                                }
                                .onEnded { _ in
                                    isKeyboardDragging = false
                                    viewModel.noteInteraction()
                                    updateOverlayCursor(
                                        hovering: isOverlayHovered,
                                        isDragging: false,
                                        allowDragCursor: allowKeyboardDrag
                                    )
                                }
                        )
                } else {
                    keyboardView
                }

                Spacer(minLength: 0)
            }
            .padding(.top, headerBottomSpacing)
            .padding(.bottom, keyboardPadding)
            .padding(.leading, keyboardPadding)
            .padding(.trailing, keyboardTrailingPadding)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: OverlayAvailableWidthPreferenceKey.self,
                        value: proxy.size.width
                    )
            }
        )
    }
}

// MARK: - Layout Handlers

private extension View {
    func overlayLayoutHandlers(
        keyboardPadding: CGFloat,
        keyboardTrailingPadding: CGFloat,
        inspectorChrome: CGFloat,
        shouldFreezeKeyboard: Bool,
        keyboardAspectRatio: CGFloat,
        verticalChrome: CGFloat,
        inspectorVisible: Bool,
        keyboardWidth: Binding<CGFloat>,
        uiState: LiveKeyboardOverlayUIState,
        viewModel: KeyboardVisualizationViewModel,
        activeLayout: PhysicalLayout,
        selectedLayoutId: String,
        isMapperAvailable: Bool,
        hasCustomRules: Bool,
        inspectorSection: InspectorSection,
        setInspectorSection: @escaping (InspectorSection) -> Void,
        setSettingsSection: @escaping (InspectorSection) -> Void,
        isSettingsShelfActive: Bool,
        setIsSettingsShelfActive: @escaping (Bool) -> Void,
        checkLauncherWelcome: @escaping () -> Void
    ) -> some View {
        onPreferenceChange(OverlayAvailableWidthPreferenceKey.self) { newValue in
            guard newValue > 0 else { return }
            let availableKeyboardWidth = max(0, newValue - keyboardPadding - keyboardTrailingPadding - inspectorChrome)
            let canUpdateWidth = keyboardWidth.wrappedValue == 0 || !shouldFreezeKeyboard
            let targetWidth = canUpdateWidth ? availableKeyboardWidth : keyboardWidth.wrappedValue
            if canUpdateWidth {
                keyboardWidth.wrappedValue = availableKeyboardWidth
            }
            guard targetWidth > 0 else { return }
            let desiredHeight = verticalChrome + (targetWidth / keyboardAspectRatio)
            if uiState.desiredContentHeight != desiredHeight {
                uiState.desiredContentHeight = desiredHeight
            }
        }
        .onChange(of: selectedLayoutId) { _, _ in
            viewModel.setLayout(activeLayout)
            uiState.keyboardAspectRatio = keyboardAspectRatio
            guard keyboardWidth.wrappedValue > 0 else { return }
            let desiredHeight = verticalChrome + (keyboardWidth.wrappedValue / keyboardAspectRatio)
            if uiState.desiredContentHeight != desiredHeight {
                uiState.desiredContentHeight = desiredHeight
            }
            if inspectorVisible {
                let totalWidth = keyboardPadding + keyboardWidth.wrappedValue + keyboardTrailingPadding + inspectorChrome
                if uiState.desiredContentWidth != totalWidth {
                    uiState.desiredContentWidth = totalWidth
                }
            }
        }
        .onChange(of: uiState.isInspectorOpen) { _, isOpen in
            if isOpen {
                if isSettingsShelfActive || inspectorSection.isSettingsShelf {
                    setIsSettingsShelfActive(false)
                }
                if !isMapperAvailable {
                    setInspectorSection(hasCustomRules ? .customRules : .launchers)
                } else if hasCustomRules, !isSettingsShelfActive {
                    setInspectorSection(.customRules)
                } else {
                    setInspectorSection(.mapper)
                }
                if inspectorSection == .launchers {
                    viewModel.loadLauncherMappings()
                }
            } else {
                viewModel.selectedKeyCode = nil
                viewModel.hoveredRuleKeyCode = nil
            }
        }
        .onChange(of: inspectorSection) { _, newSection in
            if newSection.isSettingsShelf {
                setSettingsSection(newSection)
                if !isSettingsShelfActive {
                    setIsSettingsShelfActive(true)
                }
            } else if isSettingsShelfActive {
                setIsSettingsShelfActive(false)
            }
            if newSection == .launchers {
                viewModel.loadLauncherMappings()
                checkLauncherWelcome()
            }
            if newSection != .mapper {
                viewModel.selectedKeyCode = nil
            }
            if newSection != .customRules, newSection != .launchers {
                viewModel.hoveredRuleKeyCode = nil
            }
        }
    }
}

// MARK: - Appearance

private extension View {
    func overlayAppearance(
        cornerRadius: CGFloat,
        outerHorizontalPadding: CGFloat,
        trailingOuterPadding: CGFloat,
        deepFadeAmount: CGFloat,
        reduceMotion: Bool,
        onMouseMove: @escaping () -> Void
    ) -> some View {
        clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .padding(.leading, outerHorizontalPadding)
            .padding(.trailing, trailingOuterPadding)
            .background(MouseMoveMonitor(onMove: onMouseMove))
            .opacity(0.11 + 0.89 * (1 - deepFadeAmount))
            .animation(
                reduceMotion ? nil : (deepFadeAmount > 0 ? .easeOut(duration: 0.3) : nil),
                value: deepFadeAmount
            )
    }
}

// MARK: - Cursor Tracking

private extension View {
    func overlayCursorTracking(
        isOverlayHovered: Binding<Bool>,
        isKeyboardDragging: Bool,
        isHeaderDragging: Bool,
        isHoveringHeaderButton: Bool,
        inspectorReveal: CGFloat,
        isInspectorOpen: Bool,
        isInspectorAnimating: Bool,
        allowKeyboardDrag _: Bool,
        noteInteraction: @escaping () -> Void,
        refreshCursor: @escaping () -> Void
    ) -> some View {
        onHover { hovering in
            isOverlayHovered.wrappedValue = hovering
            if hovering { noteInteraction() }
            refreshCursor()
        }
        .onChange(of: isKeyboardDragging) { _, _ in refreshCursor() }
        .onChange(of: isHeaderDragging) { _, _ in refreshCursor() }
        .onChange(of: isHoveringHeaderButton) { _, _ in refreshCursor() }
        .onChange(of: inspectorReveal) { _, _ in refreshCursor() }
        .onChange(of: isInspectorOpen) { _, _ in refreshCursor() }
        .onChange(of: isInspectorAnimating) { _, _ in refreshCursor() }
    }
}

// MARK: - LiveKeyboardOverlayView Styling Extension

extension LiveKeyboardOverlayView {
    var isDark: Bool {
        colorScheme == .dark
    }

    var overlayPanelFill: Color {
        Color(white: isDark ? 0.11 : 0.88)
    }

    @ViewBuilder
    func glassBackground(
        cornerRadius: CGFloat,
        fadeAmount: CGFloat,
        isHovered: Bool,
        isDragging: Bool
    ) -> some View {
        let dragBoost: CGFloat = isDragging ? 0.06 : 0
        let tint = isDark
            ? Color.white.opacity(0.12 - 0.07 * fadeAmount + dragBoost)
            : Color.black.opacity(0.08 - 0.04 * fadeAmount + dragBoost)

        let contactShadow = Color.black.opacity((isDark ? 0.12 : 0.08) * (1 - fadeAmount))

        let focusBorderOpacity: CGFloat = {
            if isDragging {
                return isDark ? 0.45 : 0.5
            }
            return isHovered ? (isDark ? 0.25 : 0.35) : 0
        }()
        let focusBorderColor = isDark ? Color.white : Color.black

        let baseShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            baseShape
                .fill(Color(white: isDark ? 0.1 : 0.92))
                .overlay(
                    baseShape.stroke(Color.white.opacity(isDark ? 0.08 : 0.25), lineWidth: 0.5)
                )
                .overlay(
                    baseShape.stroke(focusBorderColor.opacity(focusBorderOpacity), lineWidth: 1)
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDragging)
        } else {
            baseShape
                .fill(.ultraThinMaterial)
                .overlay(
                    baseShape.fill(tint)
                )
                .overlay(
                    baseShape.fill(Color(white: isDark ? 0.1 : 0.9).opacity(0.25 * fadeAmount))
                )
                .overlay(
                    baseShape.strokeBorder(focusBorderColor.opacity(focusBorderOpacity), lineWidth: 1)
                )
                .shadow(color: contactShadow, radius: 4, x: 0, y: 4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fadeAmount)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDragging)
        }
    }

    private func updateOverlayCursor(
        hovering: Bool,
        isDragging: Bool,
        allowDragCursor: Bool,
        isOverButton: Bool = false
    ) {
        if isDragging {
            NSCursor.closedHand.set()
            return
        }
        if isOverButton {
            NSCursor.pointingHand.set()
            return
        }
        guard allowDragCursor else {
            NSCursor.arrow.set()
            return
        }
        if hovering {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func refreshOverlayCursor(allowDragCursor: Bool) {
        updateOverlayCursor(
            hovering: isOverlayHovered,
            isDragging: isKeyboardDragging || isHeaderDragging,
            allowDragCursor: allowDragCursor,
            isOverButton: isHoveringHeaderButton
        )
    }

    private func makeInspectorContent(
        fadeAmount: CGFloat,
        inspectorTotalWidth: CGFloat,
        inspectorReveal: CGFloat,
        inspectorLeadingGap: CGFloat,
        healthIndicatorState: HealthIndicatorState,
        onHealthTap: @escaping () -> Void,
        onKeySelected: @escaping (UInt16?) -> Void,
        onRuleHover: @escaping (String?) -> Void
    ) -> some View {
        OverlayInspectorPanel(
            selectedSection: inspectorSection,
            onSelectSection: { selectInspectorSection($0) },
            fadeAmount: fadeAmount,
            isMapperAvailable: isMapperAvailable,
            kanataViewModel: kanataViewModel,
            inspectorReveal: inspectorReveal,
            inspectorTotalWidth: inspectorTotalWidth,
            inspectorLeadingGap: inspectorLeadingGap,
            healthIndicatorState: healthIndicatorState,
            onHealthTap: onHealthTap,
            onKeymapChanged: onKeymapChanged,
            isSettingsShelfActive: isSettingsShelfActive,
            onToggleSettingsShelf: toggleSettingsShelf,
            onKeySelected: onKeySelected,
            layerKeyMap: viewModel.layerKeyMap,
            hasCustomRules: hasCustomRules,
            customRules: cachedCustomRules,
            appKeymaps: appKeymaps,
            onDeleteAppRule: { keymap, override in
                deleteAppRule(keymap: keymap, override: override)
            },
            onDeleteGlobalRule: { rule in
                Task {
                    await kanataViewModel?.removeCustomRule(rule.id)
                    loadCustomRulesState()
                }
            },
            onResetAllRules: {
                showResetAllRulesConfirmation = true
            },
            onCreateNewAppRule: {
                inspectorSection = .mapper
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .openMapperAppConditionPicker, object: nil)
                }
            },
            onRuleHover: onRuleHover
        )
        .frame(width: inspectorTotalWidth, alignment: .trailing)
    }

    private func moveKeyboardWindow(deltaX: CGFloat, deltaY: CGFloat) {
        guard let window = findOverlayWindow() else { return }
        var newOrigin = keyboardDragInitialFrame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        window.setFrameOrigin(newOrigin)
    }

    private func findOverlayWindow() -> NSWindow? {
        NSApplication.shared.windows.first {
            $0.styleMask.contains(.borderless) && $0.level == .floating
        }
    }
}
