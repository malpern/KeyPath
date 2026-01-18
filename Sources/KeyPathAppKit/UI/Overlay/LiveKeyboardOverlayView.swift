import AppKit
import KeyPathCore
import SwiftUI

/// The main live keyboard overlay view.
/// Shows a borderless floating keyboard that highlights keys as they are pressed.
struct LiveKeyboardOverlayView: View {
    @ObservedObject var viewModel: KeyboardVisualizationViewModel
    @ObservedObject var uiState: LiveKeyboardOverlayUIState
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var keymapIncludePunctuationStore: String = "{}"

    @State private var escKeyLeftInset: CGFloat = 0
    @State private var keyboardWidth: CGFloat = 0
    @State private var inspectorSectionRaw: String = InspectorSection.mapper.rawValue
    @AppStorage("inspectorSettingsSection") private var settingsSectionRaw: String = InspectorSection.keyboard.rawValue
    private var inspectorSection: InspectorSection {
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

    /// Whether custom rules exist (for showing Custom Rules tab)
    @State private var hasCustomRules = false
    /// Cached global custom rules for Custom Rules tab content
    @State private var cachedCustomRules: [CustomRule] = []
    /// Cached app keymaps for Custom Rules tab content
    @State private var appKeymaps: [AppKeymap] = []
    /// Whether to show reset all rules confirmation dialog
    @State private var showResetAllRulesConfirmation = false
    /// Pending app rule deletion (for confirmation dialog)
    @State private var pendingDeleteRule: (keymap: AppKeymap, override: AppKeyOverride)?
    /// Error message for failed app rule deletion
    @State private var appRuleDeleteError: String?
    /// Japanese input mode detector for showing mode indicator
    @ObservedObject private var inputSourceDetector = InputSourceDetector.shared
    /// Whether the settings shelf is active (gear mode)
    @State private var isSettingsShelfActive = false
    /// Window drag tracking for keyboard area
    @State private var keyboardDragInitialFrame: NSRect = .zero
    @State private var keyboardDragInitialMouseLocation: NSPoint = .zero
    @State private var isKeyboardDragging = false
    @State private var isHeaderDragging = false

    /// Whether the mouse is currently hovering over the overlay (for focus indicator)
    @State private var isOverlayHovered = false
    /// Whether the mouse is hovering over a clickable header button (drawer/hide)
    @State private var isHoveringHeaderButton = false

    /// Launcher welcome dialog state (shown once per install/build)
    /// We store the build date when welcome was last shown, so it shows again on new installs
    @AppStorage("launcherWelcomeSeenForBuild") private var launcherWelcomeSeenForBuild: String = ""
    @State private var pendingLauncherConfig: LauncherGridConfig?

    /// Check if welcome should be shown for current build
    private var hasSeenLauncherWelcomeForCurrentBuild: Bool {
        let currentBuild = BuildInfo.current().date
        return launcherWelcomeSeenForBuild == currentBuild
    }

    /// Mark welcome as seen for current build
    private func markLauncherWelcomeAsSeen() {
        launcherWelcomeSeenForBuild = BuildInfo.current().date
    }

    /// The currently selected physical keyboard layout
    private var activeLayout: PhysicalLayout {
        PhysicalLayout.find(id: selectedLayoutId) ?? .macBookUS
    }

    /// The currently selected logical keymap for labeling
    private var activeKeymap: LogicalKeymap {
        LogicalKeymap.find(id: selectedKeymapId) ?? .qwertyUS
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

    var body: some View {
        let cornerRadius: CGFloat = 10 // Fixed corner radius for glass container
        let fadeAmount: CGFloat = viewModel.fadeAmount
        let headerHeight = OverlayLayoutMetrics.headerHeight
        let keyboardPadding = OverlayLayoutMetrics.keyboardPadding
        let baseKeyboardTrailingPadding = OverlayLayoutMetrics.keyboardTrailingPadding
        let headerBottomSpacing = OverlayLayoutMetrics.headerBottomSpacing
        let outerHorizontalPadding = OverlayLayoutMetrics.outerHorizontalPadding
        let inspectorReveal = uiState.inspectorReveal
        // Inspector is visible during animation or when reveal > 0 (includes fully open state)
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
        // Freeze keyboard width when inspector is visible or animating to prevent shrinking
        // This ensures the keyboard maintains its size when the drawer opens
        let shouldFreezeKeyboard = uiState.isInspectorAnimating || inspectorVisible || uiState.isInspectorOpen
        let fixedKeyboardWidth: CGFloat? = keyboardWidth > 0 ? keyboardWidth : nil
        let fixedKeyboardHeight: CGFloat? = fixedKeyboardWidth.map { $0 / keyboardAspectRatio }

        var content = AnyView(
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
                    onClose: { onClose?() },
                    onToggleInspector: { onToggleInspector?() },
                    onHealthTap: { onHealthIndicatorTap?() },
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
                            // Switch to base if we're on this layer
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
        )
        content = AnyView(content.onPreferenceChange(OverlayAvailableWidthPreferenceKey.self) { newValue in
            guard newValue > 0 else { return }
            let availableKeyboardWidth = max(0, newValue - keyboardPadding - keyboardTrailingPadding - inspectorChrome)
            let canUpdateWidth = keyboardWidth == 0 || !shouldFreezeKeyboard
            let targetWidth = canUpdateWidth ? availableKeyboardWidth : keyboardWidth
            if canUpdateWidth {
                keyboardWidth = availableKeyboardWidth
            }
            guard targetWidth > 0 else { return }
            let desiredHeight = verticalChrome + (targetWidth / keyboardAspectRatio)
            if uiState.desiredContentHeight != desiredHeight {
                uiState.desiredContentHeight = desiredHeight
            }
        })
        content = AnyView(content.onChange(of: selectedLayoutId) { _, _ in
            // Update ViewModel with new layout for correct layer mapping
            viewModel.setLayout(activeLayout)

            uiState.keyboardAspectRatio = keyboardAspectRatio
            guard keyboardWidth > 0 else { return }
            let desiredHeight = verticalChrome + (keyboardWidth / keyboardAspectRatio)
            if uiState.desiredContentHeight != desiredHeight {
                uiState.desiredContentHeight = desiredHeight
            }
            // When inspector is open and layout changes, request window resize to fit
            // keyboard + inspector without overlap
            if inspectorVisible {
                let totalWidth = keyboardPadding + keyboardWidth + keyboardTrailingPadding + inspectorChrome
                if uiState.desiredContentWidth != totalWidth {
                    uiState.desiredContentWidth = totalWidth
                }
            }
        })
        content = AnyView(content.onChange(of: inspectorSection) { _, newSection in
            if newSection.isSettingsShelf {
                settingsSection = newSection
                if !isSettingsShelfActive {
                    isSettingsShelfActive = true
                }
            } else if isSettingsShelfActive {
                isSettingsShelfActive = false
            }
            // Load launcher mappings when viewing launchers section
            if newSection == .launchers {
                viewModel.loadLauncherMappings()
                checkLauncherWelcome()
            }
            // Clear selected key when leaving mapper section
            if newSection != .mapper {
                viewModel.selectedKeyCode = nil
            }
            // Clear hovered rule key when leaving custom rules or launchers section
            if newSection != .customRules, newSection != .launchers {
                viewModel.hoveredRuleKeyCode = nil
            }
        })
        content = AnyView(content.onChange(of: uiState.isInspectorOpen) { _, isOpen in
            // Load launcher mappings when opening inspector to launchers section
            if isOpen, inspectorSection == .launchers {
                viewModel.loadLauncherMappings()
            }
            // Clear selected key and hovered rule key when closing inspector
            if !isOpen {
                viewModel.selectedKeyCode = nil
                viewModel.hoveredRuleKeyCode = nil
            }
        })
        content = AnyView(content.onAppear {
            uiState.keyboardAspectRatio = keyboardAspectRatio
            inputSourceDetector.startMonitoring()
            if !isMapperAvailable, inspectorSection == .mapper {
                inspectorSection = .keyboard
            }
            if inspectorSection.isSettingsShelf {
                settingsSection = inspectorSection
                isSettingsShelfActive = true
            }
            // Initialize ViewModel with user's selected layout
            if viewModel.layout.id != activeLayout.id {
                viewModel.setLayout(activeLayout)
            }
            // Load custom rules for Custom Rules tab
            loadCustomRulesState()
        })
        content = AnyView(content.onDisappear {
            inputSourceDetector.stopMonitoring()
        })
        content = AnyView(content.onReceive(NotificationCenter.default.publisher(for: .appKeymapsDidChange)) { _ in
            loadCustomRulesState()
        })
        // Also reload when global rules change (e.g., via mapper saving an "Everywhere" rule)
        content = AnyView(content.onReceive(NotificationCenter.default.publisher(for: .ruleCollectionsChanged)) { _ in
            loadCustomRulesState()
        })
        content = AnyView(content.onReceive(NotificationCenter.default.publisher(for: .switchToAppRulesTab)) { _ in
            // Switch to Custom Rules tab after saving a rule
            loadCustomRulesState()
            isSettingsShelfActive = false
            if hasCustomRules {
                inspectorSection = .customRules
            }
        })
        content = AnyView(content.onReceive(NotificationCenter.default.publisher(for: .switchToMapperTab)) { notification in
            // Switch to Mapper tab (from Settings "Create Rule" button)
            isSettingsShelfActive = false
            inspectorSection = .mapper

            // If preset values are provided, forward them to the mapper
            if let userInfo = notification.userInfo,
               let inputKey = userInfo["inputKey"] as? String,
               let outputKey = userInfo["outputKey"] as? String
            {
                var mapperUserInfo: [String: Any] = [
                    "inputKey": inputKey,
                    "outputKey": outputKey,
                    "keyCode": UInt16(0) // Default keyCode since we don't have it
                ]
                // Include app condition if present (for app-specific rule editing)
                if let appBundleId = userInfo["appBundleId"] as? String,
                   let appDisplayName = userInfo["appDisplayName"] as? String
                {
                    mapperUserInfo["appBundleId"] = appBundleId
                    mapperUserInfo["appDisplayName"] = appDisplayName
                }
                // Post after a small delay to ensure mapper is visible
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(
                        name: .mapperDrawerKeySelected,
                        object: nil,
                        userInfo: mapperUserInfo
                    )
                }
            }
        })
        content = AnyView(content.background(
            glassBackground(
                cornerRadius: cornerRadius,
                fadeAmount: fadeAmount,
                isHovered: isOverlayHovered,
                isDragging: isOverlayDragging
            )
        ))
        content = AnyView(content.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
        content = AnyView(content.environmentObject(viewModel))
        // Minimal padding for shadow (keep horizontal only)
        content = AnyView(content.padding(.leading, outerHorizontalPadding))
        content = AnyView(content.padding(.trailing, trailingOuterPadding))
        content = AnyView(content.onHover { hovering in
            isOverlayHovered = hovering
            if hovering { viewModel.noteInteraction() }
            refreshOverlayCursor(allowDragCursor: allowKeyboardDrag)
        })
        content = AnyView(content.onChange(of: isKeyboardDragging) { _, _ in
            refreshOverlayCursor(allowDragCursor: allowKeyboardDrag)
        })
        content = AnyView(content.onChange(of: isHeaderDragging) { _, _ in
            refreshOverlayCursor(allowDragCursor: allowKeyboardDrag)
        })
        content = AnyView(content.onChange(of: isHoveringHeaderButton) { _, _ in
            refreshOverlayCursor(allowDragCursor: allowKeyboardDrag)
        })
        content = AnyView(content.onChange(of: uiState.inspectorReveal) { _, _ in
            refreshOverlayCursor(allowDragCursor: allowKeyboardDrag)
        })
        content = AnyView(content.onChange(of: uiState.isInspectorOpen) { _, _ in
            refreshOverlayCursor(allowDragCursor: allowKeyboardDrag)
        })
        content = AnyView(content.onChange(of: uiState.isInspectorAnimating) { _, _ in
            refreshOverlayCursor(allowDragCursor: allowKeyboardDrag)
        })
        content = AnyView(content.background(MouseMoveMonitor { viewModel.noteInteraction() }))
        content = AnyView(content.opacity(0.11 + 0.89 * (1 - viewModel.deepFadeAmount)))
        // Animate deep fade smoothly; fade-in is instant
        content = AnyView(content.animation(
            reduceMotion ? nil : (viewModel.deepFadeAmount > 0 ? .easeOut(duration: 0.3) : nil),
            value: viewModel.deepFadeAmount
        ))
        // Accessibility: Make the entire overlay discoverable
        content = AnyView(content.accessibilityElement(children: .contain))
        content = AnyView(content.accessibilityIdentifier("keyboard-overlay"))
        content = AnyView(content.accessibilityLabel("KeyPath keyboard overlay"))
        // Confirmation dialog for deleting app rules
        content = AnyView(content.confirmationDialog(
            "Delete Rule?",
            isPresented: Binding(
                get: { pendingDeleteRule != nil },
                set: { if !$0 { pendingDeleteRule = nil } }
            ),
            titleVisibility: .visible,
            actions: {
                if let pending = pendingDeleteRule {
                    Button("Delete", role: .destructive) {
                        deleteAppRule(keymap: pending.keymap, override: pending.override)
                        pendingDeleteRule = nil
                    }
                    .accessibilityIdentifier("overlay-delete-app-rule-confirm-button")
                    Button("Cancel", role: .cancel) {
                        pendingDeleteRule = nil
                    }
                    .accessibilityIdentifier("overlay-delete-app-rule-cancel-button")
                }
            },
            message: {
                if let pending = pendingDeleteRule {
                    Text("Delete \(pending.override.inputKey) → \(pending.override.outputAction) for \(pending.keymap.mapping.displayName)?")
                }
            }
        ))
        // Error alert for failed deletions
        content = AnyView(content.alert(
            "Delete Failed",
            isPresented: Binding(
                get: { appRuleDeleteError != nil },
                set: { if !$0 { appRuleDeleteError = nil } }
            ),
            actions: {
                Button("OK") {
                    appRuleDeleteError = nil
                }
            },
            message: {
                if let error = appRuleDeleteError {
                    Text(error)
                }
            }
        ))
        // Confirmation dialog for resetting all custom rules
        content = AnyView(content.confirmationDialog(
            "Reset All Custom Rules?",
            isPresented: $showResetAllRulesConfirmation,
            titleVisibility: .visible,
            actions: {
                Button("Reset All", role: .destructive) {
                    resetAllCustomRules()
                }
                .accessibilityIdentifier("overlay-reset-all-custom-rules-confirm-button")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("overlay-reset-all-custom-rules-cancel-button")
            },
            message: {
                Text("This will remove all custom rules (both global and app-specific). This action cannot be undone.")
            }
        ))
        return content
    }

    @ViewBuilder
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
                        // Convert input key name to keyCode for keyboard highlighting
                        if let key = inputKey {
                            viewModel.hoveredRuleKeyCode = LogicalKeymap.keyCode(forQwertyLabel: key)
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
            // This ensures inspector doesn't show through the transparent keyboard
            // Uses solid color matching the glass appearance (opaque, not window background)
            if inspectorVisible, let kbWidth = fixedKeyboardWidth, let kbHeight = fixedKeyboardHeight {
                Rectangle()
                    .fill(Color(white: isDark ? 0.1 : 0.92))
                    .frame(width: kbWidth, height: kbHeight)
                    .padding(.top, headerBottomSpacing)
                    .padding(.leading, keyboardPadding)
            }

            // 3. Keyboard THIRD = renders on top with transparent glass
            HStack(alignment: .top, spacing: 0) {
                // Main keyboard with directional shadow (light from above)
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
                    customIcons: viewModel.customIcons,
                    onKeyClick: onKeyClick,
                    selectedKeyCode: viewModel.selectedKeyCode,
                    hoveredRuleKeyCode: viewModel.hoveredRuleKeyCode,
                    isLauncherMode: viewModel.isLauncherModeActive || (uiState.isInspectorOpen && inspectorSection == .launchers),
                    launcherMappings: viewModel.launcherMappings,
                    isInspectorVisible: inspectorVisible
                )
                .environmentObject(viewModel)
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
                        .highPriorityGesture(
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

    /// Load custom rules state (both global and app-specific)
    private func loadCustomRulesState() {
        Task {
            let keymaps = await AppKeymapStore.shared.loadKeymaps()
            await MainActor.run {
                appKeymaps = keymaps
                // Show custom rules tab if either global rules or app-specific rules exist
                // NOTE: We read underlyingManager.customRules directly to avoid race condition
                // where the notification arrives before KanataViewModel's async state update
                let globalRules = kanataViewModel?.underlyingManager.customRules ?? []
                cachedCustomRules = globalRules
                let hasGlobalRules = !globalRules.isEmpty
                let hasAppSpecificRules = !keymaps.isEmpty
                hasCustomRules = hasGlobalRules || hasAppSpecificRules
                // If we were on customRules tab but rules are gone, switch to mapper
                if !hasCustomRules, inspectorSection == .customRules {
                    inspectorSection = .mapper
                }
            }
        }
    }

    /// Delete an app-specific rule override
    private func deleteAppRule(keymap: AppKeymap, override: AppKeyOverride) {
        Task {
            // Remove the override from the keymap
            var updatedKeymap = keymap
            updatedKeymap.overrides.removeAll { $0.id == override.id }

            do {
                if updatedKeymap.overrides.isEmpty {
                    // No more overrides - remove entire keymap
                    try await AppKeymapStore.shared.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
                } else {
                    // Update keymap with remaining overrides
                    try await AppKeymapStore.shared.upsertKeymap(updatedKeymap)
                }

                // Regenerate config and reload
                try await AppConfigGenerator.regenerateFromStore()
                await AppContextService.shared.reloadMappings()

                // Restart Kanata to pick up changes
                if let kanataVM = kanataViewModel {
                    _ = await kanataVM.underlyingManager.restartKanata(reason: "App rule deleted")
                }
            } catch {
                AppLogger.shared.log("⚠️ [Overlay] Failed to delete app rule: \(error)")
                await MainActor.run {
                    appRuleDeleteError = "Failed to delete rule: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Reset all custom rules (global and app-specific)
    private func resetAllCustomRules() {
        Task {
            // Remove all global custom rules
            if let rules = kanataViewModel?.customRules {
                for rule in rules {
                    await kanataViewModel?.removeCustomRule(rule.id)
                }
            }
            // Remove all app-specific keymaps
            for keymap in appKeymaps {
                try? await AppKeymapStore.shared.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
            }
            // Reload state
            loadCustomRulesState()
        }
    }

    /// Check if launcher welcome dialog should be shown
    private func checkLauncherWelcome() {
        guard !hasSeenLauncherWelcomeForCurrentBuild else { return }

        Task {
            // Load the launcher config to pass to welcome dialog
            let collections = await RuleCollectionStore.shared.loadCollections()
            if let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
               let config = launcherCollection.configuration.launcherGridConfig
            {
                await MainActor.run {
                    pendingLauncherConfig = config
                    showLauncherWelcomeWindow()
                }
            }
        }
    }

    /// Show the launcher welcome dialog as an independent centered window
    private func showLauncherWelcomeWindow() {
        guard let config = pendingLauncherConfig else { return }

        LauncherWelcomeWindowController.show(
            config: Binding(
                get: { [self] in pendingLauncherConfig ?? config },
                set: { [self] in pendingLauncherConfig = $0 }
            ),
            onComplete: { [self] finalConfig, _ in
                handleLauncherWelcomeComplete(finalConfig)
            },
            onDismiss: { [self] in
                // User closed without completing - still mark as seen for this build
                markLauncherWelcomeAsSeen()
                pendingLauncherConfig = nil
            }
        )
    }

    /// Handle launcher welcome dialog completion
    private func handleLauncherWelcomeComplete(_ finalConfig: LauncherGridConfig) {
        var updatedConfig = finalConfig
        updatedConfig.hasSeenWelcome = true
        markLauncherWelcomeAsSeen()

        // Save the updated config
        Task {
            let collections = await RuleCollectionStore.shared.loadCollections()
            if var launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                launcherCollection.configuration = .launcherGrid(updatedConfig)
                // Update the collections array and save
                var allCollections = collections
                if let index = allCollections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                    allCollections[index] = launcherCollection
                    try? await RuleCollectionStore.shared.saveCollections(allCollections)
                }
            }
        }

        pendingLauncherConfig = nil
    }
}

// MARK: - LiveKeyboardOverlayView Styling Extension

extension LiveKeyboardOverlayView {
    var isDark: Bool { colorScheme == .dark }
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
        // Simulated "liquid glass" backdrop: adaptive material + tint + softened shadows.
        let dragBoost: CGFloat = isDragging ? 0.06 : 0
        let tint = isDark
            ? Color.white.opacity(0.12 - 0.07 * fadeAmount + dragBoost)
            : Color.black.opacity(0.08 - 0.04 * fadeAmount + dragBoost)

        let contactShadow = Color.black.opacity((isDark ? 0.12 : 0.08) * (1 - fadeAmount))

        // Subtle focus border when hovering - very light so it's not distracting
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
                // Focus indicator border
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
                // Fade overlay: animating material .opacity() directly causes discrete jumps,
                // so we overlay a semi-transparent wash that fades in smoothly instead
                .overlay(
                    baseShape.fill(Color(white: isDark ? 0.1 : 0.9).opacity(0.25 * fadeAmount))
                )
                // Focus indicator border - subtle inner glow effect
                .overlay(
                    baseShape.strokeBorder(focusBorderColor.opacity(focusBorderOpacity), lineWidth: 1)
                )
                // y >= radius ensures shadow only renders below (light from above)
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
        // Pointing hand for clickable buttons (drawer, hide)
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
    ) -> AnyView {
        AnyView(
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
                    // Delete immediately (no confirmation for single rule)
                    deleteAppRule(keymap: keymap, override: override)
                },
                onDeleteGlobalRule: { rule in
                    // Delete global rule through KanataViewModel
                    Task {
                        await kanataViewModel?.removeCustomRule(rule.id)
                        loadCustomRulesState()
                    }
                },
                onResetAllRules: {
                    showResetAllRulesConfirmation = true
                },
                onCreateNewAppRule: {
                    // Switch to mapper tab and trigger app picker to open
                    inspectorSection = .mapper
                    // Delay notification to allow mapper view to render and subscribe
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NotificationCenter.default.post(name: .openMapperAppConditionPicker, object: nil)
                    }
                },
                onRuleHover: onRuleHover
            )
            .frame(width: inspectorTotalWidth, alignment: .trailing)
        )
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

// MARK: - Overlay Drag Header + Inspector

/// Subtle dimpled texture to indicate the draggable header area.
/// Uses a dot pattern that suggests "grip" without affecting readability.
private struct DragHandleTexture: View {
    let isDark: Bool

    var body: some View {
        Canvas { context, size in
            let dotSpacing: CGFloat = 4
            let dotRadius: CGFloat = 0.5
            // Subtle opacity that doesn't interfere with readability
            let dotColor = isDark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.06)

            // Draw dots in a grid pattern
            var y: CGFloat = dotSpacing / 2
            while y < size.height {
                var x: CGFloat = dotSpacing / 2
                while x < size.width {
                    let rect = CGRect(
                        x: x - dotRadius,
                        y: y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    context.fill(Circle().path(in: rect), with: .color(dotColor))
                    x += dotSpacing
                }
                y += dotSpacing
            }
        }
    }
}

/// A tooltip modifier that uses a separate floating window (avoids clipping issues)
private struct WindowTooltip: ViewModifier {
    let text: String
    let id: String

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onHover { hovering in
                            if hovering {
                                // Convert local frame to screen coordinates
                                if let window = NSApp.windows.first(where: { $0.isVisible && $0.level == .floating }) {
                                    let localFrame = geo.frame(in: .global)
                                    let windowFrame = window.frame
                                    let screenRect = NSRect(
                                        x: windowFrame.origin.x + localFrame.origin.x,
                                        y: windowFrame.origin.y + windowFrame.height - localFrame.origin.y - localFrame.height,
                                        width: localFrame.width,
                                        height: localFrame.height
                                    )
                                    TooltipWindowController.shared.show(text: text, id: id, anchorRect: screenRect)
                                }
                            } else {
                                TooltipWindowController.shared.dismiss(id: id)
                            }
                        }
                }
            )
    }
}

private extension View {
    func windowTooltip(_ text: String, id: String) -> some View {
        modifier(WindowTooltip(text: text, id: id))
    }
}

private struct OverlayDragHeader: View {
    let isDark: Bool
    let fadeAmount: CGFloat
    let height: CGFloat
    let inspectorWidth: CGFloat
    let reduceTransparency: Bool
    let isInspectorOpen: Bool
    @Binding var isDragging: Bool
    /// Whether mouse is hovering over a clickable button (for cursor)
    @Binding var isHoveringButton: Bool
    /// Japanese input mode indicator (あ/ア/A) - nil when not in Japanese mode
    let inputModeIndicator: String?
    /// Current layer name from Kanata
    let currentLayerName: String
    /// Whether launcher mode is active (drawer open with Quick Launch selected)
    let isLauncherMode: Bool
    /// Whether Kanata TCP server is connected (receiving events)
    let isKanataConnected: Bool
    /// Current system health indicator state
    let healthIndicatorState: HealthIndicatorState
    /// Whether the drawer button should be visually highlighted (hotkey feedback)
    let drawerButtonHighlighted: Bool
    let onClose: () -> Void
    let onToggleInspector: () -> Void
    /// Callback when health indicator is tapped (to launch wizard)
    let onHealthTap: () -> Void
    /// Callback when a layer is selected in the picker
    let onLayerSelected: (String) -> Void
    /// Callback when a new layer is created
    var onCreateLayer: ((String) -> Void)?
    /// Callback when a layer is deleted
    var onDeleteLayer: ((String) -> Void)?

    @State private var initialFrame: NSRect = .zero
    @State private var initialMouseLocation: NSPoint = .zero
    @State private var isLayerPickerOpen = false
    @State private var availableLayers: [String] = ["base", "nav"]
    /// Whether the layer pill is expanded (showing name) or collapsed (icon only)
    @State private var isLayerPillExpanded = true
    /// Whether mouse is hovering over the layer pill
    @State private var isHoveringLayerPill = false
    /// Timer to auto-collapse the layer pill after showing layer name
    @State private var layerCollapseTimer: Timer?
    /// Timer for grace period after mouse leaves before starting collapse
    @State private var layerGracePeriodTimer: Timer?
    /// Tracks the last layer name to detect changes
    @State private var lastLayerName: String = ""
    /// Whether the new layer sheet is showing
    @State private var showingNewLayerSheet = false
    /// New layer name being entered
    @State private var newLayerName = ""
    /// Layer being hovered for delete button
    @State private var hoveredLayer: String?
    /// Computed arrow edge for layer picker (up by default, down near screen top)
    @State private var layerPickerArrowEdge: Edge = .top

    /// System layers that cannot be deleted
    private static let systemLayers: Set<String> = ["base", "nav", "navigation", "launcher"]

    /// Check if a layer is a system layer (cannot be deleted)
    private func isSystemLayer(_ layer: String) -> Bool {
        Self.systemLayers.contains(layer.lowercased())
    }

    // MARK: - Layer Pill Timing Constants
    private let layerPillInitialCollapseDelay: TimeInterval = 2.0
    private let layerPillHoverCollapseDelay: TimeInterval = 10.0
    private let layerPillGracePeriod: TimeInterval = 0.4

    private var layerDisplayName: String {
        if isLauncherMode { return "Launcher" }
        return currentLayerName.lowercased() == "base" ? "Base" : currentLayerName.capitalized
    }

    /// Whether we're in a non-base layer (including launcher mode)
    private var isNonBaseLayer: Bool {
        isLauncherMode || currentLayerName.lowercased() != "base"
    }

    /// Whether to show the layer/Japanese input indicators (hidden until health is good)
    private var shouldShowStatusIndicators: Bool {
        healthIndicatorState == .dismissed
    }

    var body: some View {
        let buttonSize = max(10, height * 0.9)
        let indicatorCornerRadius: CGFloat = 4

        HStack(spacing: 0) {
            // Flexible spacer pushes controls to the trailing edge
            Spacer()

            // Controls aligned to the right side of the header
            // Order: Status indicators (left) → Drawer → Close (far right)
            HStack(spacing: 6) {
                // 1. Status slot (leftmost of the right-aligned group):
                // - Shows health indicator when not dismissed (including the "Ready" pill)
                // - Otherwise shows Japanese input + layer pill
                statusSlot(indicatorCornerRadius: indicatorCornerRadius, buttonSize: buttonSize)

                // 2. Toggle inspector/drawer button
                Button {
                    AppLogger.shared.log("🔘 [Header] Toggle drawer button clicked - isInspectorOpen=\(isInspectorOpen)")
                    onToggleInspector()
                } label: {
                    Image(systemName: isInspectorOpen ? "xmark.circle" : "slider.horizontal.3")
                        .font(.system(size: buttonSize * 0.6, weight: .semibold))
                        .foregroundStyle(drawerButtonHighlighted ? Color.accentColor : headerIconColor)
                        .frame(width: buttonSize, height: buttonSize)
                        .scaleEffect(drawerButtonHighlighted ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: drawerButtonHighlighted)
                }
                .modifier(GlassButtonStyleModifier(reduceTransparency: reduceTransparency))
                .onHover { isHoveringButton = $0 }
                .windowTooltip(isInspectorOpen ? "Close Settings" : "Open Settings", id: "drawer")
                .accessibilityIdentifier("overlay-drawer-toggle")
                .accessibilityLabel(isInspectorOpen ? "Close settings drawer" : "Open settings drawer")

                // 3. Hide button (rightmost) - hides overlay, use ⌘⌥K to bring back
                Button {
                    AppLogger.shared.log("🔘 [Header] Hide button clicked")
                    print("🔘 [Header] Hide button clicked")
                    onClose()
                } label: {
                    Image(systemName: "eye.slash")
                        .font(.system(size: buttonSize * 0.6, weight: .semibold))
                        .foregroundStyle(headerIconColor)
                        .frame(width: buttonSize, height: buttonSize)
                }
                .modifier(GlassButtonStyleModifier(reduceTransparency: reduceTransparency))
                .onHover { isHoveringButton = $0 }
                .windowTooltip("Hide Overlay (⌘⌥K)", id: "hide")
                .accessibilityIdentifier("overlay-hide-button")
                .accessibilityLabel("Hide keyboard overlay")
            }
            .padding(.trailing, 6)
            .animation(.easeOut(duration: 0.12), value: currentLayerName)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: healthIndicatorState)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: height)
        .clipped()
        .background(DragHandleTexture(isDark: isDark))
        .contentShape(Rectangle())
        // Use simultaneousGesture so child buttons can still receive taps
        // Increased minimumDistance to 5 to distinguish taps from drags
        .simultaneousGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { _ in
                    if !isDragging {
                        if let window = findOverlayWindow() {
                            initialFrame = window.frame
                            initialMouseLocation = NSEvent.mouseLocation
                        }
                        isDragging = true
                    }
                    let currentMouse = NSEvent.mouseLocation
                    let deltaX = currentMouse.x - initialMouseLocation.x
                    let deltaY = currentMouse.y - initialMouseLocation.y
                    moveWindow(deltaX: deltaX, deltaY: deltaY)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onAppear {
            refreshAvailableLayers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ruleCollectionsChanged)) { _ in
            refreshAvailableLayers()
        }
        .onChange(of: isInspectorOpen) { _, _ in
            // Dismiss tooltips when drawer opens/closes so they don't get stuck
            // in their old position during animation
            TooltipWindowController.shared.dismissImmediately()
        }
    }

    /// Refresh available layers from rule collections
    private func refreshAvailableLayers() {
        Task {
            let collections = await RuleCollectionStore.shared.loadCollections()
            var layers = Set<String>(["base", "nav"])

            // Add layers from enabled rule collections
            for collection in collections where collection.isEnabled {
                // Add the collection's target layer
                layers.insert(collection.targetLayer.kanataName)

                // Also add layer from momentary activator if present
                if let activator = collection.momentaryActivator {
                    layers.insert(activator.targetLayer.kanataName)
                }
            }

            // Also include current layer if not in list (e.g., from TCP)
            layers.insert(currentLayerName.lowercased())

            await MainActor.run {
                availableLayers = layers.sorted { a, b in
                    // Base always first, then alphabetical
                    if a == "base" { return true }
                    if b == "base" { return false }
                    return a < b
                }
            }
        }
    }

    private var headerTint: Color {
        headerFill
    }

    private var headerFill: Color {
        // Transparent to let the glass material show through
        Color.clear
    }

    private var headerIconColor: Color {
        Color.white.opacity(isDark ? 0.7 : 0.6)
    }

    @ViewBuilder
    private func statusSlot(indicatorCornerRadius: CGFloat, buttonSize: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            if healthIndicatorState != .dismissed {
                SystemHealthIndicatorView(
                    state: healthIndicatorState,
                    isDark: isDark,
                    indicatorCornerRadius: indicatorCornerRadius,
                    onTap: onHealthTap
                )
            } else {
                HStack(spacing: 6) {
                    if !isKanataConnected {
                        kanataDisconnectedPill(indicatorCornerRadius: indicatorCornerRadius)
                    }

                    if let inputModeIndicator {
                        inputModePill(
                            indicator: inputModeIndicator,
                            indicatorCornerRadius: indicatorCornerRadius
                        )
                    }

                    // Always show layer indicator (including base layer)
                    layerPill(
                        layerDisplayName: layerDisplayName,
                        indicatorCornerRadius: indicatorCornerRadius,
                        buttonSize: buttonSize
                    )
                    .id(layerDisplayName) // Force new view when layer changes
                    .transition(.move(edge: .top))
                    .animation(.easeOut(duration: 0.2), value: layerDisplayName)
                }
                .transition(.opacity)
            }
        }
        // Don't expand to fill space - let Nav pill stay close to drawer button
        .fixedSize(horizontal: true, vertical: false)
    }

    private func inputModePill(indicator: String, indicatorCornerRadius: CGFloat) -> some View {
        let modeName = switch indicator {
        case "あ": "Hiragana"
        case "ア": "Katakana"
        case "A": "Alphanumeric"
        default: "Japanese"
        }

        return Text(indicator)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(headerIconColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: indicatorCornerRadius)
                    .fill(Color.white.opacity(isDark ? 0.1 : 0.15))
            )
            .help("Japanese Input Mode: \(modeName)")
            .accessibilityIdentifier("overlay-input-mode-indicator")
            .accessibilityLabel("Japanese input mode: \(modeName)")
    }

    /// Whether the layer pill should show the full name (expanded state, hovering, or picker open)
    private var shouldShowLayerName: Bool {
        isLayerPillExpanded || isHoveringLayerPill || isLayerPickerOpen
    }

    /// Background opacity for layer pill - brightens slightly on hover
    private var layerPillBackgroundOpacity: Double {
        let baseOpacity = isDark ? 0.1 : 0.15
        return isHoveringLayerPill ? baseOpacity + 0.08 : baseOpacity
    }

    /// Spring animation for smooth layer pill transitions
    private var layerPillSpring: Animation {
        .spring(response: 0.35, dampingFraction: 0.8)
    }

    @ViewBuilder
    private func layerPill(layerDisplayName: String, indicatorCornerRadius: CGFloat, buttonSize: CGFloat) -> some View {
        let iconName = layerIconName(for: layerDisplayName)

        Group {
            if shouldShowLayerName {
                // Expanded: pill style with name, using glass effect
                Button {
                    toggleLayerPicker()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: iconName)
                            .font(.system(size: 10, weight: .medium))
                        Text(layerDisplayName)
                            .font(.system(size: 9, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .opacity(0.7)
                    }
                    .foregroundStyle(headerIconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .modifier(GlassEffectModifier(
                        isEnabled: !reduceTransparency,
                        cornerRadius: indicatorCornerRadius,
                        fallbackFill: Color.white.opacity(layerPillBackgroundOpacity)
                    ))
                }
                .buttonStyle(.plain)
            } else {
                // Collapsed: icon-only, matches other header buttons exactly
                Button {
                    toggleLayerPicker()
                } label: {
                    Image(systemName: iconName)
                        .font(.system(size: buttonSize * 0.6, weight: .semibold))
                        .foregroundStyle(headerIconColor)
                        .frame(width: buttonSize, height: buttonSize)
                }
                .modifier(GlassButtonStyleModifier(reduceTransparency: reduceTransparency))
            }
        }
        .animation(layerPillSpring, value: shouldShowLayerName)
        .animation(.easeInOut(duration: 0.15), value: isHoveringLayerPill)
        // Extend hit area by 4px on all sides for easier targeting
        .padding(4)
        .contentShape(Rectangle())
        .padding(-4)
        .onHover { hovering in
            handleLayerPillHover(hovering)
        }
        .popover(isPresented: $isLayerPickerOpen, arrowEdge: layerPickerArrowEdge) {
            layerPickerPopover
        }
        .sheet(isPresented: $showingNewLayerSheet) {
            NewLayerSheet(
                layerName: $newLayerName,
                existingLayers: availableLayers,
                onSubmit: { name in
                    onCreateLayer?(name)
                    newLayerName = ""
                    showingNewLayerSheet = false
                },
                onCancel: {
                    newLayerName = ""
                    showingNewLayerSheet = false
                }
            )
        }
        .onChange(of: currentLayerName) { _, newValue in
            handleLayerNameChange(newValue)
        }
        .onAppear {
            // Initialize lastLayerName and start initial collapse timer
            lastLayerName = currentLayerName
            scheduleLayerPillCollapse(delay: layerPillInitialCollapseDelay)
        }
        .help("Current layer: \(layerDisplayName). Click to see available layers.")
        .accessibilityIdentifier("overlay-layer-indicator")
        .accessibilityLabel("Current layer: \(layerDisplayName). Click to see available layers.")
    }

    /// Handle hover state changes with grace period
    private func handleLayerPillHover(_ hovering: Bool) {
        // Cancel any pending grace period timer
        layerGracePeriodTimer?.invalidate()
        layerGracePeriodTimer = nil

        if hovering {
            // Mouse entered - cancel collapse and expand immediately
            layerCollapseTimer?.invalidate()
            isHoveringLayerPill = true

            // If collapsed, expand with animation
            if !isLayerPillExpanded {
                withAnimation(layerPillSpring) {
                    isLayerPillExpanded = true
                }
            }
        } else {
            // Mouse left - start grace period before actually marking as not hovering
            layerGracePeriodTimer = Timer.scheduledTimer(withTimeInterval: layerPillGracePeriod, repeats: false) { _ in
                DispatchQueue.main.async {
                    isHoveringLayerPill = false
                    // Schedule collapse with longer delay since user was engaged
                    scheduleLayerPillCollapse(delay: layerPillHoverCollapseDelay)
                }
            }
        }
    }

    /// Handle layer name changes - expand the pill and schedule collapse
    private func handleLayerNameChange(_ newLayerName: String) {
        // Only expand if layer actually changed
        guard newLayerName != lastLayerName else { return }
        lastLayerName = newLayerName

        // Cancel any timers
        layerCollapseTimer?.invalidate()
        layerGracePeriodTimer?.invalidate()

        // Expand the pill to show the new layer name
        withAnimation(layerPillSpring) {
            isLayerPillExpanded = true
        }

        // Schedule collapse after showing the name (use initial delay for layer changes)
        scheduleLayerPillCollapse(delay: layerPillInitialCollapseDelay)
    }

    /// Schedule the layer pill to collapse after a delay
    private func scheduleLayerPillCollapse(delay: TimeInterval) {
        // Cancel any existing timer
        layerCollapseTimer?.invalidate()

        // Schedule collapse
        layerCollapseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            DispatchQueue.main.async {
                // Don't collapse if hovering or picker is open
                guard !isHoveringLayerPill, !isLayerPickerOpen else { return }
                withAnimation(layerPillSpring) {
                    isLayerPillExpanded = false
                }
            }
        }
    }

    /// Toggle layer picker with smart positioning (opens up by default, down near screen top)
    private func toggleLayerPicker() {
        if isLayerPickerOpen {
            // Closing - just toggle
            isLayerPickerOpen = false
        } else {
            // Opening - compute arrow edge first
            layerPickerArrowEdge = computeLayerPickerArrowEdge()
            isLayerPickerOpen = true
        }
    }

    /// Compute which edge the popover arrow should point from based on available screen space
    private func computeLayerPickerArrowEdge() -> Edge {
        guard let window = findOverlayWindow(),
              let screen = window.screen ?? NSScreen.main else {
            return .top // Default to opening upward
        }

        let windowTop = window.frame.maxY
        let screenTop = screen.visibleFrame.maxY
        let spaceAbove = screenTop - windowTop

        // Estimate popover height (layers + new layer option + padding)
        // Each row is ~40pt, header/footer ~12pt
        let estimatedRowHeight: CGFloat = 40
        let estimatedPopoverHeight = CGFloat(availableLayers.count + 1) * estimatedRowHeight + 24

        // If not enough space above, open downward (arrowEdge: .bottom)
        // Add some margin (20pt) for safety
        if spaceAbove < estimatedPopoverHeight + 20 {
            return .bottom
        }

        return .top
    }

    /// Popover showing available layers
    private var layerPickerPopover: some View {
        VStack(spacing: 0) {
            ForEach(Array(availableLayers.enumerated()), id: \.element) { index, layer in
                layerPickerRow(layer: layer, index: index)

                if index < availableLayers.count - 1 {
                    Divider()
                        .opacity(0.2)
                        .padding(.horizontal, 8)
                }
            }

            Divider()
                .opacity(0.2)
                .padding(.horizontal, 8)

            // New Layer option - styled same as layer rows
            Button {
                isLayerPickerOpen = false
                showingNewLayerSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.body)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    Text("New Layer...")
                        .font(.body)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerButtonStyle())
            .focusable(false)
            .accessibilityIdentifier("layer-picker-new")
        }
        .padding(.vertical, 6)
        .frame(minWidth: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .padding(4)
    }

    /// Individual layer row in the picker
    @ViewBuilder
    private func layerPickerRow(layer: String, index: Int) -> some View {
        let displayName = layer.lowercased() == "base" ? "Base" : layer.capitalized
        let isCurrentLayer = currentLayerName.lowercased() == layer.lowercased()
        let layerIcon = layerIconName(for: displayName)
        let canDelete = !isSystemLayer(layer)
        let isHovered = hoveredLayer == layer

        HStack(spacing: 0) {
            Button {
                isLayerPickerOpen = false
                onLayerSelected(layer)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: layerIcon)
                        .font(.body)
                        .frame(width: 20)
                        .foregroundStyle(isCurrentLayer ? Color.accentColor : .secondary)
                    Text(displayName)
                        .font(.body)
                    Spacer()
                    if isCurrentLayer {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(LayerPickerButtonStyle())
            .focusable(false)

            // Delete button for user-created layers (hover only)
            if canDelete {
                Button {
                    isLayerPickerOpen = false
                    onDeleteLayer?(layer)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .opacity(isHovered ? 1 : 0)
                .accessibilityIdentifier("layer-delete-\(layer)")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isCurrentLayer ? 0.05 : (isHovered ? 0.03 : 0)))
        )
        .onHover { hovering in
            hoveredLayer = hovering ? layer : nil
        }
    }

    /// Button style for layer picker items (no focus ring)
    private struct LayerPickerButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
                )
        }
    }

    private func layerIconName(for layerDisplayName: String) -> String {
        let lower = layerDisplayName.lowercased()

        switch lower {
        case "base":
            return "keyboard"
        case "nav", "navigation", "vim":
            return "arrow.up.and.down.and.arrow.left.and.right"
        case "window", "window-mgmt":
            return "macwindow"
        case "numpad", "num":
            return "number"
        case "sym", "symbol":
            return "character"
        case "launcher", "quick launcher":
            return "app.badge"
        default:
            return "square.3.layers.3d"
        }
    }

    private func kanataDisconnectedPill(indicatorCornerRadius: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 9, weight: .medium))
            Text("No TCP")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.orange.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: indicatorCornerRadius)
                .fill(Color.orange.opacity(isDark ? 0.15 : 0.2))
        )
        .help("Not receiving events from Kanata")
        .accessibilityIdentifier("overlay-kanata-disconnected-indicator")
        .accessibilityLabel("Not connected to Kanata TCP server")
    }

    private func moveWindow(deltaX: CGFloat, deltaY: CGFloat) {
        guard let window = findOverlayWindow() else { return }
        var newOrigin = initialFrame.origin
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

// MARK: - System Health Indicator View

/// Displays system health status in the overlay header.
/// Shows spinner during checking, green check when healthy, orange warning when unhealthy.
private struct SystemHealthIndicatorView: View {
    let state: HealthIndicatorState
    let isDark: Bool
    let indicatorCornerRadius: CGFloat
    let onTap: () -> Void

    private var headerIconColor: Color {
        Color.white.opacity(isDark ? 0.7 : 0.6)
    }

    var body: some View {
        Group {
            switch state {
            case .checking:
                // Spinner while health is being calculated
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("Checking...")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(headerIconColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: indicatorCornerRadius)
                        .fill(Color.white.opacity(isDark ? 0.1 : 0.15))
                )

            case .healthy:
                // Green checkmark - briefly visible before fading
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                    Text("Ready")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(headerIconColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: indicatorCornerRadius)
                        .fill(Color.green.opacity(0.15))
                )
                .transition(.opacity.combined(with: .scale))

            case let .unhealthy(issueCount):
                // Orange warning - clickable to launch wizard
                Button {
                    AppLogger.shared.log("🔘 [Health] Issues button tapped - launching wizard")
                    onTap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                        Text(issueCount == 1 ? "1 Issue" : "\(issueCount) Issues")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: indicatorCornerRadius)
                            .fill(Color.orange.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: indicatorCornerRadius)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded {
                    AppLogger.shared.log("🔘 [Health] Issues button tap gesture - launching wizard")
                    onTap()
                })
                .help("Click to fix system issues")
                .accessibilityIdentifier("overlay-health-indicator-error")
                .accessibilityLabel("System has \(issueCount) issue\(issueCount == 1 ? "" : "s"). Click to fix.")
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .opacity
                ))

            case .dismissed:
                EmptyView()
            }
        }
        .accessibilityIdentifier("overlay-health-indicator")
    }
}

private struct OverlayAvailableWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RightRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct InspectorMaskedHost<Content: View>: NSViewRepresentable {
    var content: Content
    var reveal: CGFloat
    var totalWidth: CGFloat
    var leadingGap: CGFloat
    var slideOffset: CGFloat
    var opacity: CGFloat
    var debugEnabled: Bool

    func makeNSView(context _: Context) -> InspectorMaskedHostingView<Content> {
        InspectorMaskedHostingView(content: content)
    }

    func updateNSView(_ nsView: InspectorMaskedHostingView<Content>, context _: Context) {
        nsView.update(
            content: content,
            reveal: reveal,
            totalWidth: totalWidth,
            leadingGap: leadingGap,
            slideOffset: slideOffset,
            opacity: opacity,
            debugEnabled: debugEnabled
        )
    }
}

private final class InspectorMaskedHostingView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private let maskLayer = CALayer()
    private var reveal: CGFloat = 0
    private var totalWidth: CGFloat = 0
    private var leadingGap: CGFloat = 0
    private var slideOffset: CGFloat = 0
    private var contentOpacity: CGFloat = 1
    private var debugEnabled: Bool = false
    private var lastDebugLogTime: CFTimeInterval = 0

    init(content: Content) {
        hostingView = NSHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.mask = maskLayer
        maskLayer.backgroundColor = NSColor.black.cgColor

        hostingView.wantsLayer = true
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        content: Content,
        reveal: CGFloat,
        totalWidth: CGFloat,
        leadingGap: CGFloat,
        slideOffset: CGFloat,
        opacity: CGFloat,
        debugEnabled: Bool
    ) {
        hostingView.rootView = content
        self.reveal = reveal
        self.totalWidth = totalWidth
        self.leadingGap = leadingGap
        self.slideOffset = slideOffset
        contentOpacity = opacity
        self.debugEnabled = debugEnabled
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let bounds = bounds
        hostingView.frame = bounds.offsetBy(dx: slideOffset, dy: 0)
        hostingView.alphaValue = contentOpacity

        let widthBasis = totalWidth > 0 ? totalWidth : bounds.width
        let gap = max(0, min(leadingGap, widthBasis))
        let panelWidth = max(0, widthBasis - gap)
        let width = max(0, min(widthBasis, gap + panelWidth * reveal))
        maskLayer.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)

        guard debugEnabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDebugLogTime > 0.2 else { return }
        lastDebugLogTime = now
        let revealStr = String(format: "%.3f", reveal)
        let slideStr = String(format: "%.1f", slideOffset)
        let widthStr = String(format: "%.1f", width)
        let gapStr = String(format: "%.1f", gap)
        let opacityStr = String(format: "%.2f", contentOpacity)
        AppLogger.shared.log(
            "🧱 [OverlayInspectorMask] bounds=\(bounds.size.debugDescription) reveal=\(revealStr) slide=\(slideStr) gap=\(gapStr) maskW=\(widthStr) opacity=\(opacityStr)"
        )
    }
}

struct OverlayInspectorPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let selectedSection: InspectorSection
    let onSelectSection: (InspectorSection) -> Void
    let fadeAmount: CGFloat
    let isMapperAvailable: Bool
    let kanataViewModel: KanataViewModel?
    let inspectorReveal: CGFloat
    let inspectorTotalWidth: CGFloat
    let inspectorLeadingGap: CGFloat
    let healthIndicatorState: HealthIndicatorState
    let onHealthTap: () -> Void
    /// Callback when keymap selection changes (keymapId, includePunctuation)
    var onKeymapChanged: ((String, Bool) -> Void)?
    /// Whether settings shelf (gear mode) is active
    let isSettingsShelfActive: Bool
    /// Toggle settings shelf (gear mode)
    let onToggleSettingsShelf: () -> Void
    /// Callback when a key is selected in the mapper drawer (keyCode or nil to clear)
    var onKeySelected: ((UInt16?) -> Void)?
    /// Layer key map for looking up actual mappings (passed from parent view)
    var layerKeyMap: [UInt16: LayerKeyInfo] = [:]
    /// Whether custom rules exist (for showing Custom Rules tab)
    var hasCustomRules: Bool = false
    /// Global custom rules for displaying in Custom Rules tab
    var customRules: [CustomRule] = []
    /// App keymaps for displaying in Custom Rules tab
    var appKeymaps: [AppKeymap] = []
    /// Callback when an app rule is deleted
    var onDeleteAppRule: ((AppKeymap, AppKeyOverride) -> Void)?
    /// Callback when a global rule is deleted
    var onDeleteGlobalRule: ((CustomRule) -> Void)?
    /// Callback when user wants to reset all custom rules
    var onResetAllRules: (() -> Void)?
    /// Callback when user wants to create a new app rule
    var onCreateNewAppRule: (() -> Void)?
    /// Callback when hovering a rule row - passes inputKey for keyboard highlighting
    var onRuleHover: ((String?) -> Void)?

    @AppStorage(KeymapPreferences.keymapIdKey) private var selectedKeymapId: String = LogicalKeymap.defaultId
    @AppStorage(KeymapPreferences.includePunctuationStoreKey) private var includePunctuationStore: String = "{}"
    @AppStorage(LayoutPreferences.layoutIdKey) private var selectedLayoutId: String = LayoutPreferences.defaultLayoutId
    @AppStorage("overlayColorwayId") private var selectedColorwayId: String = GMKColorway.default.id

    /// Category to scroll to in physical layout grid
    @State private var scrollToLayoutCategory: LayoutCategory?

    /// Which slide-over panel is currently open (nil = none)
    @State private var activeDrawerPanel: DrawerPanel?

    /// Binding for whether any panel is open
    private var isPanelPresented: Binding<Bool> {
        Binding(
            get: { activeDrawerPanel != nil },
            set: { if !$0 { activeDrawerPanel = nil } }
        )
    }

    /// Title for the currently open panel
    private var panelTitle: String {
        activeDrawerPanel?.title ?? ""
    }

    private var includePunctuation: Bool {
        KeymapPreferences.includePunctuation(for: selectedKeymapId, store: includePunctuationStore)
    }

    private var visibleInspectorWidth: CGFloat {
        let gap = max(0, min(inspectorLeadingGap, inspectorTotalWidth))
        let panelWidth = max(0, inspectorTotalWidth - gap)
        let width = gap + panelWidth * inspectorReveal
        return max(0, min(inspectorTotalWidth, width))
    }

    var body: some View {
        let showDrawerDebugOutline = false
        // SlideOverContainer wraps entire drawer content (tabs + content) so panel covers everything
        SlideOverContainer(
            isPresented: isPanelPresented,
            panelTitle: panelTitle,
            mainContent: {
                VStack(spacing: 8) {
                    // Toolbar with section tabs
                    InspectorPanelToolbar(
                        isDark: isDark,
                        selectedSection: selectedSection,
                        onSelectSection: onSelectSection,
                        isMapperAvailable: isMapperAvailable,
                        healthIndicatorState: healthIndicatorState,
                        hasCustomRules: hasCustomRules,
                        isSettingsShelfActive: isSettingsShelfActive,
                        onToggleSettingsShelf: onToggleSettingsShelf
                    )

                    // Content based on selected section
                    if selectedSection == .launchers {
                        // Launchers section fills available space with button pinned to bottom
                        launchersContent
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    } else if selectedSection == .mapper {
                        // Mapper section fills available space with layer button pinned to bottom
                        mapperContent
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    } else if selectedSection == .layout {
                        // Physical layout has its own ScrollView with ScrollViewReader for anchoring
                        physicalLayoutContent
                    } else if selectedSection == .customRules {
                        // Custom rules browser (global + app-specific)
                        customRulesContent
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                switch selectedSection {
                                case .mapper:
                                    EmptyView() // Handled above
                                case .keyboard:
                                    keymapsContent
                                case .layout:
                                    EmptyView() // Handled above
                                case .keycaps:
                                    keycapsContent
                                case .sounds:
                                    soundsContent
                                case .launchers:
                                    EmptyView() // Handled above
                                case .customRules:
                                    EmptyView() // Handled above
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                        }
                    }
                }
            },
            panelContent: {
                switch activeDrawerPanel {
                case .tapHold:
                    tapHoldPanelContent
                case .launcherSettings:
                    launcherCustomizePanelContent
                case nil:
                    EmptyView()
                }
            }
        )
        .saturation(Double(1 - fadeAmount)) // Monochromatic when faded
        .opacity(Double(1 - fadeAmount * 0.5)) // Fade with keyboard
        .onChange(of: selectedKeymapId) { _, newValue in
            onKeymapChanged?(newValue, includePunctuation)
        }
        .onChange(of: includePunctuationStore) { _, _ in
            onKeymapChanged?(selectedKeymapId, includePunctuation)
        }
        .overlay(alignment: .leading) {
            if showDrawerDebugOutline {
                GeometryReader { proxy in
                    let width = min(proxy.size.width, visibleInspectorWidth)
                    Rectangle()
                        .stroke(Color.red.opacity(0.9), lineWidth: 1)
                        .frame(width: width, height: proxy.size.height, alignment: .leading)
                }
                .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTapHoldPanel)) { notification in
            // Extract key info from notification
            if let keyLabel = notification.userInfo?["keyLabel"] as? String {
                tapHoldKeyLabel = keyLabel
            }
            if let keyCode = notification.userInfo?["keyCode"] as? UInt16 {
                tapHoldKeyCode = keyCode
            }
            // Extract selected slot
            if let slotRaw = notification.userInfo?["slot"] as? String,
               let slot = BehaviorSlot(rawValue: slotRaw) {
                tapHoldInitialSlot = slot
            }
            // Open the Tap & Hold panel
            withAnimation(.easeInOut(duration: 0.25)) {
                activeDrawerPanel = .tapHold
            }
        }
    }

    // MARK: - Custom Rules Content

    @ViewBuilder
    private var customRulesContent: some View {
        VStack(spacing: 0) {
            // Scrollable list of rule cards (no header - title removed)
            ScrollView {
                LazyVStack(spacing: 10) {
                    // "Everywhere" section for global rules (only shown when rules exist)
                    if !customRules.isEmpty {
                        GlobalRulesCard(
                            rules: customRules,
                            onEdit: { rule in
                                editGlobalRule(rule: rule)
                            },
                            onDelete: { rule in
                                onDeleteGlobalRule?(rule)
                            },
                            onAddRule: {
                                // Switch to mapper with no app condition (global/everywhere)
                                onSelectSection(.mapper)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    NotificationCenter.default.post(
                                        name: .mapperSetAppCondition,
                                        object: nil,
                                        userInfo: ["bundleId": "", "displayName": ""]
                                    )
                                }
                            },
                            onRuleHover: onRuleHover
                        )
                    }

                    // App-specific rules
                    ForEach(appKeymaps) { keymap in
                        AppRuleCard(
                            keymap: keymap,
                            onEdit: { override in
                                editAppRule(keymap: keymap, override: override)
                            },
                            onDelete: { override in
                                onDeleteAppRule?(keymap, override)
                            },
                            onAddRule: {
                                addRuleForApp(keymap: keymap)
                            },
                            onRuleHover: onRuleHover
                        )
                    }
                }
            }

            Spacer()

            // Bottom action bar with reset and add buttons (anchored to bottom right)
            HStack {
                Spacer()
                // Reset all rules button
                Button(action: { onResetAllRules?() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom-rules-reset-button")
                .accessibilityLabel("Reset all custom rules")
                .help("Reset all custom rules")

                // New rule button
                Button(action: { onCreateNewAppRule?() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("custom-rules-new-button")
                .accessibilityLabel("Create new custom rule")
                .help("Create new custom rule")
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Custom Rules Actions

    private func editAppRule(keymap: AppKeymap, override: AppKeyOverride) {
        // Open mapper with this app's context and rule preloaded
        // Use UserDefaults directly since @AppStorage can't be accessed from nested functions
        UserDefaults.standard.set(InspectorSection.mapper.rawValue, forKey: "inspectorSection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let userInfo: [String: Any] = [
                "keyCode": UInt16(0),
                "inputKey": override.inputKey,
                "outputKey": override.outputAction,
                "appBundleId": keymap.mapping.bundleIdentifier,
                "appDisplayName": keymap.mapping.displayName
            ]
            NotificationCenter.default.post(
                name: .mapperDrawerKeySelected,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    private func addRuleForApp(keymap: AppKeymap) {
        // Open mapper with this app's context (no rule preloaded)
        // Use UserDefaults directly since @AppStorage can't be accessed from nested functions
        UserDefaults.standard.set(InspectorSection.mapper.rawValue, forKey: "inspectorSection")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Set the app condition on the mapper view model
            NotificationCenter.default.post(
                name: .mapperSetAppCondition,
                object: nil,
                userInfo: [
                    "bundleId": keymap.mapping.bundleIdentifier,
                    "displayName": keymap.mapping.displayName
                ]
            )
        }
    }

    private func editGlobalRule(rule: CustomRule) {
        // Open mapper with the global rule preloaded (no app condition)
        onSelectSection(.mapper)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let userInfo: [String: Any] = [
                "keyCode": UInt16(0),
                "inputKey": rule.input,
                "outputKey": rule.output
                // No appBundleId means global/everywhere
            ]
            NotificationCenter.default.post(
                name: .mapperDrawerKeySelected,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    // MARK: - Keymaps Content

    @ViewBuilder
    private var keymapsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Alt layouts section (QWERTY + ergonomic layouts) - no header
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // QWERTY first
                KeymapCard(
                    keymap: LogicalKeymap.qwertyUS,
                    isSelected: selectedKeymapId == LogicalKeymap.qwertyUS.id,
                    isDark: isDark,
                    fadeAmount: fadeAmount
                ) {
                    selectedKeymapId = LogicalKeymap.qwertyUS.id
                }

                // Then alt layouts
                ForEach(LogicalKeymap.altLayouts) { keymap in
                    KeymapCard(
                        keymap: keymap,
                        isSelected: selectedKeymapId == keymap.id,
                        isDark: isDark,
                        fadeAmount: fadeAmount
                    ) {
                        selectedKeymapId = keymap.id
                    }
                }
            }

            // International layouts section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("International")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                }
                .padding(.leading, 4)
                .padding(.trailing, 4)
                .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(LogicalKeymap.internationalLayouts) { keymap in
                        KeymapCard(
                            keymap: keymap,
                            isSelected: selectedKeymapId == keymap.id,
                            isDark: isDark,
                            fadeAmount: fadeAmount
                        ) {
                            selectedKeymapId = keymap.id
                        }
                    }
                }
            }

            // Link to international physical layouts
            Button {
                onSelectSection(.layout)
                // Set scroll target after tab switch to ensure view is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    scrollToLayoutCategory = .international
                }
            } label: {
                HStack(spacing: 4) {
                    Text("International physical layouts")
                        .font(.system(size: 11))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityIdentifier("international-physical-layouts-link")
        }
    }

    // MARK: - Mapper Content

    @ViewBuilder
    private var mapperContent: some View {
        if case .unhealthy = healthIndicatorState {
            OverlayMapperSection(
                isDark: isDark,
                kanataViewModel: kanataViewModel,
                healthIndicatorState: healthIndicatorState,
                onHealthTap: onHealthTap,
                fadeAmount: fadeAmount,
                onKeySelected: onKeySelected,
                layerKeyMap: layerKeyMap
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if healthIndicatorState == .checking {
            OverlayMapperSection(
                isDark: isDark,
                kanataViewModel: kanataViewModel,
                healthIndicatorState: healthIndicatorState,
                onHealthTap: onHealthTap,
                fadeAmount: fadeAmount,
                onKeySelected: onKeySelected,
                layerKeyMap: layerKeyMap
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if isMapperAvailable {
            OverlayMapperSection(
                isDark: isDark,
                kanataViewModel: kanataViewModel,
                healthIndicatorState: healthIndicatorState,
                onHealthTap: onHealthTap,
                fadeAmount: fadeAmount,
                onKeySelected: onKeySelected,
                layerKeyMap: layerKeyMap
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            unavailableSection(
                title: "Mapper Unavailable",
                message: "Finish setup to enable quick remapping in the overlay."
            )
        }
    }

    // MARK: - Tap & Hold Panel State (Apple-style 80/20 design)

    /// Key label being configured in the Tap & Hold panel
    @State private var tapHoldKeyLabel: String = "A"
    /// Key code being configured
    @State private var tapHoldKeyCode: UInt16? = 0
    /// Initially selected behavior slot when panel opens
    @State private var tapHoldInitialSlot: BehaviorSlot = .tap
    /// Tap behavior action
    @State private var tapHoldTapAction: BehaviorAction = .key("a")
    /// Hold behavior action
    @State private var tapHoldHoldAction: BehaviorAction = .none
    /// Double tap behavior action
    @State private var tapHoldDoubleTapAction: BehaviorAction = .none
    /// Tap + Hold behavior action
    @State private var tapHoldTapHoldAction: BehaviorAction = .none
    /// Responsiveness level (maps to timing thresholds)
    @State private var tapHoldResponsiveness: ResponsivenessLevel = .balanced
    /// Use tap immediately when typing starts
    @State private var tapHoldUseTapImmediately: Bool = true

    // MARK: - Legacy Customize Panel State (deprecated - use Tap & Hold panel)

    /// Hold action for tap-hold configuration
    @State private var customizeHoldAction: String = ""
    /// Double tap action
    @State private var customizeDoubleTapAction: String = ""
    /// Additional tap-dance steps (Triple Tap, Quad Tap, etc.)
    @State private var customizeTapDanceSteps: [(label: String, action: String)] = []
    /// Tap timeout in milliseconds
    @State private var customizeTapTimeout: Int = 200
    /// Hold timeout in milliseconds
    @State private var customizeHoldTimeout: Int = 200
    /// Whether to show separate tap/hold timing fields
    @State private var customizeShowTimingAdvanced: Bool = false
    /// Which field is currently recording (nil = none)
    @State private var customizeRecordingField: String? = nil
    /// Local event monitor for key capture
    @State private var customizeKeyMonitor: Any? = nil

    // MARK: - Launcher Customize Panel State
    /// Current launcher activation mode
    @State private var launcherActivationMode: LauncherActivationMode = .holdHyper
    /// Current hyper trigger mode (hold vs tap)
    @State private var launcherHyperTriggerMode: HyperTriggerMode = .hold
    /// Whether browser history sheet is showing
    @State private var showLauncherHistorySuggestions = false

    /// Labels for tap-dance steps beyond double tap
    private static let tapDanceLabels = ["Triple Tap", "Quad Tap", "Quint Tap"]

    /// Content for the Tap & Hold slide-over panel (Apple-style 80/20 design)
    private var tapHoldPanelContent: some View {
        TapHoldCardView(
            keyLabel: tapHoldKeyLabel,
            keyCode: tapHoldKeyCode,
            initialSlot: tapHoldInitialSlot,
            tapAction: $tapHoldTapAction,
            holdAction: $tapHoldHoldAction,
            doubleTapAction: $tapHoldDoubleTapAction,
            tapHoldAction: $tapHoldTapHoldAction,
            responsiveness: $tapHoldResponsiveness,
            useTapImmediately: $tapHoldUseTapImmediately
        )
        .padding(.horizontal, 4)
    }

    /// Content for the slide-over customize panel - tap-hold focused (legacy)
    private var customizePanelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // On Hold row
            customizeRow(
                label: "On Hold",
                action: customizeHoldAction,
                fieldId: "hold",
                onClear: { customizeHoldAction = "" }
            )

            // Double Tap row
            customizeRow(
                label: "Double Tap",
                action: customizeDoubleTapAction,
                fieldId: "doubleTap",
                onClear: { customizeDoubleTapAction = "" }
            )

            // Triple+ Tap rows (dynamically added)
            ForEach(Array(customizeTapDanceSteps.enumerated()), id: \.offset) { index, step in
                customizeTapDanceRow(index: index, step: step)
            }

            // "+ Triple Tap" link (only if we can add more)
            if customizeTapDanceSteps.count < Self.tapDanceLabels.count {
                HStack(spacing: 16) {
                    Text("")
                        .frame(width: 70)

                    Button {
                        let label = Self.tapDanceLabels[customizeTapDanceSteps.count]
                        customizeTapDanceSteps.append((label: label, action: ""))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                            Text(Self.tapDanceLabels[customizeTapDanceSteps.count])
                                .font(.subheadline)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("customize-add-tap-dance")
                    .accessibilityLabel("Add \(Self.tapDanceLabels[customizeTapDanceSteps.count])")

                    Spacer()
                }
            }

            // Timing row
            customizeTimingRow

            Spacer()
        }
        .padding(.horizontal, 12)
        .onDisappear {
            stopCustomizeRecording()
        }
    }

    /// Content for the launcher customize slide-over panel
    private var launcherCustomizePanelContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Activation Mode section
            VStack(alignment: .leading, spacing: 8) {
                Picker("Activation Mode", selection: $launcherActivationMode) {
                    Text(LauncherActivationMode.holdHyper.displayName)
                        .tag(LauncherActivationMode.holdHyper)
                    Text(LauncherActivationMode.leaderSequence.displayName)
                        .tag(LauncherActivationMode.leaderSequence)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("launcher-customize-activation-mode")
                .onChange(of: launcherActivationMode) { _, newMode in
                    saveLauncherConfig()
                }

                // Hyper trigger mode segmented picker (only when Hyper mode selected)
                if launcherActivationMode == .holdHyper {
                    Picker("Trigger Mode", selection: $launcherHyperTriggerMode) {
                        Text(HyperTriggerMode.hold.displayName)
                            .tag(HyperTriggerMode.hold)
                        Text(HyperTriggerMode.tap.displayName)
                            .tag(HyperTriggerMode.tap)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("launcher-customize-trigger-picker")
                    .onChange(of: launcherHyperTriggerMode) { _, _ in
                        saveLauncherConfig()
                    }
                }

                // Description text
                Text(launcherActivationDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Suggest from History button
            Button {
                showLauncherHistorySuggestions = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.body)
                    Text("Suggest from Browser History")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("launcher-customize-suggest-history")

            Spacer()
        }
        .padding(.horizontal, 12)
        .onAppear {
            loadLauncherConfig()
        }
        .sheet(isPresented: $showLauncherHistorySuggestions) {
            BrowserHistorySuggestionsView { selectedSites in
                addSuggestedSitesToLauncher(selectedSites)
            }
        }
    }

    /// Description for launcher activation mode
    private var launcherActivationDescription: String {
        switch launcherActivationMode {
        case .holdHyper:
            launcherHyperTriggerMode.description + " Then press a shortcut key."
        case .leaderSequence:
            "Press Leader, then L, then press a shortcut key."
        }
    }

    /// Load launcher config from store
    private func loadLauncherConfig() {
        Task {
            let collections = await RuleCollectionStore.shared.loadCollections()
            if let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
               let config = launcherCollection.configuration.launcherGridConfig {
                await MainActor.run {
                    launcherActivationMode = config.activationMode
                    launcherHyperTriggerMode = config.hyperTriggerMode
                }
            }
        }
    }

    /// Save launcher config to store
    private func saveLauncherConfig() {
        Task {
            var collections = await RuleCollectionStore.shared.loadCollections()
            if let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                var collection = collections[index]
                if var config = collection.configuration.launcherGridConfig {
                    config.activationMode = launcherActivationMode
                    config.hyperTriggerMode = launcherHyperTriggerMode
                    collection.configuration = .launcherGrid(config)
                    collections[index] = collection
                    try? await RuleCollectionStore.shared.saveCollections(collections)
                    // Notify that rules changed so config regenerates
                    NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
                }
            }
        }
    }

    /// Add suggested sites from browser history to launcher
    private func addSuggestedSitesToLauncher(_ sites: [BrowserHistoryScanner.VisitedSite]) {
        Task {
            var collections = await RuleCollectionStore.shared.loadCollections()
            if let index = collections.firstIndex(where: { $0.id == RuleCollectionIdentifier.launcher }) {
                var collection = collections[index]
                if var config = collection.configuration.launcherGridConfig {
                    // Get existing keys
                    var existingKeys = Set(config.mappings.map { $0.key.lowercased() })

                    // Add new mappings for each suggested site
                    for site in sites {
                        // Find next available letter
                        let alphabet = "asdfghjklqwertyuiopzxcvbnm"
                        guard let key = alphabet.first(where: { !existingKeys.contains(String($0)) }).map({ String($0) }) else {
                            continue
                        }

                        existingKeys.insert(key)

                        let mapping = LauncherMapping(
                            key: key,
                            target: .url("https://\(site.domain)")
                        )
                        config.mappings.append(mapping)
                    }

                    collection.configuration = .launcherGrid(config)
                    collections[index] = collection
                    try? await RuleCollectionStore.shared.saveCollections(collections)
                    NotificationCenter.default.post(name: .ruleCollectionsChanged, object: nil)
                }
            }
        }
    }

    /// Start recording for a specific field
    private func startCustomizeRecording(fieldId: String) {
        // Stop any existing recording first
        stopCustomizeRecording()

        customizeRecordingField = fieldId

        // Add local key event monitor
        customizeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Get the key name from the event
            let keyName = keyNameFromEvent(event)

            // Update the appropriate field
            DispatchQueue.main.async {
                self.setCustomizeFieldValue(fieldId: fieldId, value: keyName)
                self.stopCustomizeRecording()
            }

            // Consume the event so it doesn't propagate
            return nil
        }
    }

    /// Stop any active recording
    private func stopCustomizeRecording() {
        if let monitor = customizeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            customizeKeyMonitor = nil
        }
        customizeRecordingField = nil
    }

    /// Toggle recording for a field
    private func toggleCustomizeRecording(fieldId: String) {
        if customizeRecordingField == fieldId {
            stopCustomizeRecording()
        } else {
            startCustomizeRecording(fieldId: fieldId)
        }
    }

    /// Set the value for a customize field by ID
    private func setCustomizeFieldValue(fieldId: String, value: String) {
        switch fieldId {
        case "hold":
            customizeHoldAction = value
        case "doubleTap":
            customizeDoubleTapAction = value
        default:
            // Handle tap-dance steps (e.g., "tapDance-0")
            if fieldId.hasPrefix("tapDance-"),
               let indexStr = fieldId.split(separator: "-").last,
               let index = Int(indexStr),
               index < customizeTapDanceSteps.count
            {
                customizeTapDanceSteps[index].action = value
            }
        }
    }

    /// Convert NSEvent to a key name string
    private func keyNameFromEvent(_ event: NSEvent) -> String {
        // Check for modifier-only keys first
        let flags = event.modifierFlags

        // Map common keyCodes to kanata key names
        let keyCodeMap: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "ret",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "spc",
            50: "`", 51: "bspc", 53: "esc",
            // Modifiers
            54: "rsft", 55: "lmet", 56: "lsft", 57: "caps", 58: "lalt",
            59: "lctl", 60: "rsft", 61: "ralt", 62: "rctl",
            // Function keys
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
            98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
            // Arrow keys
            123: "left", 124: "right", 125: "down", 126: "up",
            // Other
            117: "del", 119: "end", 121: "pgdn", 115: "home", 116: "pgup",
        ]

        if let keyName = keyCodeMap[event.keyCode] {
            // Build modifier prefix if any non-modifier key
            var result = ""
            if flags.contains(.control) { result += "C-" }
            if flags.contains(.option) { result += "A-" }
            if flags.contains(.shift), !["lsft", "rsft"].contains(keyName) { result += "S-" }
            if flags.contains(.command) { result += "M-" }
            return result + keyName
        }

        // Fallback to characters
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            return chars.lowercased()
        }

        return "unknown"
    }

    /// A row for hold/double-tap action with mini keycap
    private func customizeRow(label: String, action: String, fieldId: String, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            TapHoldMiniKeycap(
                label: action.isEmpty ? "" : formatKeyForCustomize(action),
                isRecording: customizeRecordingField == fieldId,
                onTap: {
                    toggleCustomizeRecording(fieldId: fieldId)
                }
            )
            .accessibilityIdentifier("customize-\(fieldId)-keycap")
            .accessibilityLabel("\(label) action keycap")

            if !action.isEmpty {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("customize-\(fieldId)-clear")
                .accessibilityLabel("Clear \(label.lowercased()) action")
            }

            Spacer()
        }
    }

    /// A row for tap-dance steps (triple tap, quad tap, etc.)
    private func customizeTapDanceRow(index: Int, step: (label: String, action: String)) -> some View {
        HStack(spacing: 12) {
            Text(step.label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            TapHoldMiniKeycap(
                label: step.action.isEmpty ? "" : formatKeyForCustomize(step.action),
                isRecording: customizeRecordingField == "tapDance-\(index)",
                onTap: {
                    toggleCustomizeRecording(fieldId: "tapDance-\(index)")
                }
            )
            .accessibilityIdentifier("customize-tapDance-\(index)-keycap")
            .accessibilityLabel("\(step.label) action keycap")

            if !step.action.isEmpty {
                Button {
                    customizeTapDanceSteps[index].action = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("customize-tapDance-\(index)-clear")
                .accessibilityLabel("Clear \(step.label.lowercased()) action")
            }

            // Remove button
            Button {
                customizeTapDanceSteps.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("customize-tapDance-\(index)-remove")
            .accessibilityLabel("Remove \(step.label.lowercased())")

            Spacer()
        }
    }

    /// Timing configuration row
    private var customizeTimingRow: some View {
        HStack(spacing: 12) {
            Text("Timing")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            if customizeShowTimingAdvanced {
                // Separate tap/hold fields
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tap")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("", value: $customizeTapTimeout, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .accessibilityIdentifier("customize-tap-timeout")
                                .accessibilityLabel("Tap timeout in milliseconds")
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hold")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("", value: $customizeHoldTimeout, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .accessibilityIdentifier("customize-hold-timeout")
                                .accessibilityLabel("Hold timeout in milliseconds")
                        }
                        Text("ms")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Single timing value
                HStack(spacing: 8) {
                    TextField("", value: $customizeTapTimeout, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .accessibilityIdentifier("customize-timing")
                        .accessibilityLabel("Timing in milliseconds")

                    Text("ms")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Gear icon to toggle advanced timing
            Button {
                customizeShowTimingAdvanced.toggle()
                if customizeShowTimingAdvanced {
                    customizeHoldTimeout = customizeTapTimeout
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline)
                    .foregroundColor(customizeShowTimingAdvanced ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("customize-timing-advanced-toggle")
            .accessibilityLabel(customizeShowTimingAdvanced ? "Use single timing value" : "Use separate tap and hold timing")

            Spacer()
        }
    }

    /// Format a key name for display in customize panel
    private func formatKeyForCustomize(_ key: String) -> String {
        // Handle common modifier names
        switch key.lowercased() {
        case "lmet", "rmet", "met": return "⌘"
        case "lalt", "ralt", "alt": return "⌥"
        case "lctl", "rctl", "ctl": return "⌃"
        case "lsft", "rsft", "sft": return "⇧"
        case "space", "spc": return "␣"
        case "ret", "return", "enter": return "↩"
        case "bspc", "backspace": return "⌫"
        case "tab": return "⇥"
        case "esc", "escape": return "⎋"
        default: return key.uppercased()
        }
    }

    // MARK: - Physical Layout Content

    @ViewBuilder
    private var physicalLayoutContent: some View {
        KeyboardSelectionGridView(
            selectedLayoutId: $selectedLayoutId,
            isDark: isDark,
            scrollToCategory: $scrollToLayoutCategory
        )
        // Stable identity prevents scroll position reset when parent re-renders
        // (e.g., when modifier keys like Command trigger pressedKeyCodes updates)
        .id("physical-layout-grid")
    }

    // MARK: - Keycaps Content

    @ViewBuilder
    private var keycapsContent: some View {
        // Colorway cards in 2-column grid
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(GMKColorway.all) { colorway in
                ColorwayCard(
                    colorway: colorway,
                    isSelected: selectedColorwayId == colorway.id,
                    isDark: isDark
                ) {
                    selectedColorwayId = colorway.id
                }
            }
        }
    }

    // MARK: - Sounds Content

    @ViewBuilder
    private var soundsContent: some View {
        TypingSoundsSection(isDark: isDark)
    }

    // MARK: - Launchers Content

    @ViewBuilder
    private var launchersContent: some View {
        OverlayLaunchersSection(
            isDark: isDark,
            fadeAmount: fadeAmount,
            onMappingHover: onRuleHover,
            onCustomize: { activeDrawerPanel = .launcherSettings }
        )
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private func unavailableSection(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: isDark ? 0.16 : 0.94))
        )
    }
}

/// Card view for a single keymap option with SVG image and info button
private struct KeymapCard: View {
    let keymap: LogicalKeymap
    let isSelected: Bool
    let isDark: Bool
    let fadeAmount: CGFloat
    let onSelect: () -> Void

    @State private var isHovering = false
    @State private var svgImage: NSImage?

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                // SVG Image - becomes monochromatic when fading
                if let image = svgImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 45)
                        .saturation(Double(1 - fadeAmount)) // Monochromatic when faded
                } else {
                    keymapPlaceholder
                        .frame(height: 45)
                }

                // Label with info button
                HStack(spacing: 4) {
                    Text(keymap.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Button {
                        NSWorkspace.shared.open(keymap.learnMoreURL)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-keymap-button-\(keymap.id)")
        .accessibilityLabel("Select keymap \(keymap.name)")
        .onHover { isHovering = $0 }
        .onAppear { loadSVG() }
    }

    private func loadSVG() {
        // SVGs are at bundle root (not in subdirectory) due to .process() flattening
        guard let svgURL = Bundle.module.url(
            forResource: keymap.iconFilename,
            withExtension: "svg"
        ) else { return }

        svgImage = NSImage(contentsOf: svgURL)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected
                ? Color.accentColor.opacity(0.15)
                : (isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
    }

    private var keymapPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "keyboard")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            )
    }
}

/// Card view for a GMK colorway option with color swatch preview
private struct ColorwayCard: View {
    let colorway: GMKColorway
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                // Color swatch preview (horizontal bars)
                colorSwatchPreview
                    .frame(height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Name and designer
                VStack(spacing: 1) {
                    Text(colorway.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Text(colorway.designer)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay-colorway-button-\(colorway.id)")
        .accessibilityLabel("Select colorway \(colorway.name)")
        .onHover { isHovering = $0 }
        .help("\(colorway.name) by \(colorway.designer) (\(colorway.year))")
    }

    /// Horizontal color bars showing the colorway
    private var colorSwatchPreview: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                // Alpha base (largest - main key color)
                colorway.alphaBaseColor
                    .frame(width: geo.size.width * 0.35)

                // Mod base
                colorway.modBaseColor
                    .frame(width: geo.size.width * 0.25)

                // Accent base
                colorway.accentBaseColor
                    .frame(width: geo.size.width * 0.2)

                // Legend color (shows as small bar)
                colorway.alphaLegendColor
                    .frame(width: geo.size.width * 0.2)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected
                ? Color.accentColor.opacity(0.15)
                : (isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
    }
}

/// Row view for a physical layout option
private struct PhysicalLayoutRow: View {
    let layout: PhysicalLayout
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: layoutIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 24)

                Text(layout.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityIdentifier("overlay-layout-button-\(layout.id)")
            .accessibilityLabel("Select layout \(layout.name)")
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var layoutIcon: String {
        switch layout.id {
        case "macbook-us": "laptopcomputer"
        case "kinesis-360": "keyboard"
        default: "keyboard"
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected
                ? Color.accentColor.opacity(0.15)
                : (isHovering ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
    }
}

private enum GearAnchorLocation: Hashable {
    case main
    case settings
}

private struct GearAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [GearAnchorLocation: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [GearAnchorLocation: Anchor<CGRect>],
        nextValue: () -> [GearAnchorLocation: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct InspectorPanelToolbar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isDark: Bool
    let selectedSection: InspectorSection
    let onSelectSection: (InspectorSection) -> Void
    let isMapperAvailable: Bool
    let healthIndicatorState: HealthIndicatorState
    let hasCustomRules: Bool
    let isSettingsShelfActive: Bool
    let onToggleSettingsShelf: () -> Void
    private let buttonSize: CGFloat = 32
    @State private var isHoveringMapper = false
    @State private var isHoveringCustomRules = false
    @State private var isHoveringKeyboard = false
    @State private var isHoveringLayout = false
    @State private var isHoveringKeycaps = false
    @State private var isHoveringSounds = false
    @State private var isHoveringLaunchers = false
    @State private var isHoveringSettings = false
    @State private var showMainTabs = true
    @State private var showSettingsTabs = false
    @State private var animationToken = 0
    @State private var gearSpinDegrees: Double = 0
    @State private var gearTravelDistance: CGFloat = 0
    @State private var gearPositionX: CGFloat = 0
    @State private var gearPositionY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            mainTabsRow
            settingsTabsRow
        }
        .overlayPreferenceValue(GearAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                let mainFrame = anchors[.main].map { proxy[$0] }
                let settingsFrame = anchors[.settings].map { proxy[$0] }
                if let mainFrame, let settingsFrame {
                    gearButton(isSelected: showSettingsTabs, rotationDegrees: gearRotationDegrees)
                        .accessibilityIdentifier("inspector-tab-settings")
                        .position(x: gearPositionX, y: gearPositionY)
                        .zIndex(1)
                        .onAppear {
                            // Set initial position without animation
                            let initialFrame = isSettingsShelfActive ? settingsFrame : mainFrame
                            gearPositionX = initialFrame.midX
                            gearPositionY = initialFrame.midY
                            updateGearTravelDistance(mainFrame: mainFrame, settingsFrame: settingsFrame)
                        }
                        .onChange(of: mainFrame) { _, newValue in
                            updateGearTravelDistance(mainFrame: newValue, settingsFrame: settingsFrame)
                            if !isSettingsShelfActive {
                                updateGearPosition(to: newValue)
                            }
                        }
                        .onChange(of: settingsFrame) { _, newValue in
                            updateGearTravelDistance(mainFrame: mainFrame, settingsFrame: newValue)
                            if isSettingsShelfActive {
                                updateGearPosition(to: newValue)
                            }
                        }
                        .onChange(of: isSettingsShelfActive) { _, isActive in
                            let targetFrame = isActive ? settingsFrame : mainFrame
                            updateGearPosition(to: targetFrame)
                        }
                }
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // No background - transparent toolbar
        .onAppear {
            syncShelfVisibility()
        }
        .onChange(of: isSettingsShelfActive) { _, newValue in
            animateShelfTransition(isActive: newValue)
        }
    }

    private var mainTabsRow: some View {
        HStack(spacing: 8) {
            mainTabsContent
                .opacity(showMainTabs ? 1 : 0)
                .allowsHitTesting(showMainTabs)
                .accessibilityHidden(!showMainTabs)
            gearAnchor(.main)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var settingsTabsRow: some View {
        HStack(spacing: 8) {
            gearAnchor(.settings)
            settingsTabsContent
                .opacity(showSettingsTabs ? 1 : 0)
                .allowsHitTesting(showSettingsTabs)
                .accessibilityHidden(!showSettingsTabs)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var gearSlideDuration: Double {
        reduceMotion ? 0 : 0.7 // 4x faster than previous (2.8 / 4)
    }

    private var gearSpinDuration: Double {
        reduceMotion ? 0 : 0.6 // 60% reduction from original (1.5 * 0.4)
    }

    private var tabFadeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.16)
    }

    private var gearRotationDegrees: Double {
        reduceMotion ? 0 : gearSpinDegrees
    }

    private func gearButton(isSelected: Bool, rotationDegrees: Double) -> some View {
        Button(action: onToggleSettingsShelf) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: buttonSize * 0.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : (isHoveringSettings ? .primary : .secondary))
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: buttonSize, height: buttonSize)
                .background(gearBackground(isSelected: isSelected))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inspector-tab-settings")
        .accessibilityLabel(isSelected ? "Close settings shelf" : "Open settings shelf")
        .help("Settings")
        .onHover { isHoveringSettings = $0 }
    }

    private func gearBackground(isSelected: Bool) -> some View {
        let selectedFill = Color.accentColor.opacity(isDark ? 0.38 : 0.26)
        let hoverFill = (isDark ? Color.white : Color.black).opacity(isDark ? 0.08 : 0.08)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? selectedFill : (isHoveringSettings ? hoverFill : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(isDark ? 0.9 : 0.7) : Color.clear, lineWidth: 1.5)
            )
    }

    private func toolbarButton(
        systemImage: String,
        isSelected: Bool,
        isHovering: Bool,
        onHover: @escaping (Bool) -> Void,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: buttonSize * 0.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : (isHovering ? .primary : .secondary))
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("overlay-toolbar-button-\(systemImage)")
        .accessibilityLabel("Toolbar button \(systemImage)")
        .onHover(perform: onHover)
    }

    private var isMapperTabEnabled: Bool {
        if healthIndicatorState == .checking { return true }
        if case .unhealthy = healthIndicatorState { return true }
        return isMapperAvailable
    }

    private var mainTabsContent: some View {
        Group {
            // Mapper first (leftmost)
            toolbarButton(
                systemImage: "arrow.right.arrow.left",
                isSelected: selectedSection == .mapper,
                isHovering: isHoveringMapper,
                onHover: { isHoveringMapper = $0 }
            ) {
                onSelectSection(.mapper)
            }
            .disabled(!isMapperTabEnabled)
            .opacity(isMapperTabEnabled ? 1 : 0.45)
            .accessibilityIdentifier("inspector-tab-mapper")
            .accessibilityLabel("Key Mapper")
            .help("Key Mapper")

            // Custom Rules (only shown when custom rules exist)
            if hasCustomRules {
                toolbarButton(
                    systemImage: "list.bullet.rectangle",
                    isSelected: selectedSection == .customRules,
                    isHovering: isHoveringCustomRules,
                    onHover: { isHoveringCustomRules = $0 }
                ) {
                    onSelectSection(.customRules)
                }
                .accessibilityIdentifier("inspector-tab-custom-rules")
                .accessibilityLabel("Custom Rules")
                .help("Custom Rules")
            }

            // Launchers
            toolbarButton(
                systemImage: "bolt.fill",
                isSelected: selectedSection == .launchers,
                isHovering: isHoveringLaunchers,
                onHover: { isHoveringLaunchers = $0 }
            ) {
                onSelectSection(.launchers)
            }
            .accessibilityIdentifier("inspector-tab-launchers")
            .accessibilityLabel("Quick Launcher")
            .help("Quick Launcher")
        }
    }

    private var settingsTabsContent: some View {
        Group {
            // Keymap (Logical Layout) first
            toolbarButton(
                systemImage: "keyboard",
                isSelected: selectedSection == .keyboard,
                isHovering: isHoveringKeyboard,
                onHover: { isHoveringKeyboard = $0 }
            ) {
                onSelectSection(.keyboard)
            }
            .accessibilityIdentifier("inspector-tab-keymap")
            .accessibilityLabel("Keymap")
            .help("Keymap")

            toolbarButton(
                systemImage: "square.grid.3x2",
                isSelected: selectedSection == .layout,
                isHovering: isHoveringLayout,
                onHover: { isHoveringLayout = $0 }
            ) {
                onSelectSection(.layout)
            }
            .accessibilityIdentifier("inspector-tab-layout")
            .accessibilityLabel("Physical Layout")
            .help("Physical Layout")

            toolbarButton(
                systemImage: "swatchpalette.fill",
                isSelected: selectedSection == .keycaps,
                isHovering: isHoveringKeycaps,
                onHover: { isHoveringKeycaps = $0 }
            ) {
                onSelectSection(.keycaps)
            }
            .accessibilityIdentifier("inspector-tab-keycaps")
            .accessibilityLabel("Keycap Style")
            .help("Keycap Style")

            toolbarButton(
                systemImage: "speaker.wave.2.fill",
                isSelected: selectedSection == .sounds,
                isHovering: isHoveringSounds,
                onHover: { isHoveringSounds = $0 }
            ) {
                onSelectSection(.sounds)
            }
            .accessibilityIdentifier("inspector-tab-sounds")
            .accessibilityLabel("Typing Sounds")
            .help("Typing Sounds")
        }
    }

    private func gearAnchor(_ location: GearAnchorLocation) -> some View {
        Color.clear
            .frame(width: buttonSize, height: buttonSize)
            .anchorPreference(key: GearAnchorPreferenceKey.self, value: .bounds) { [location: $0] }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func syncShelfVisibility() {
        showMainTabs = !isSettingsShelfActive
        showSettingsTabs = isSettingsShelfActive
    }

    private func animateShelfTransition(isActive: Bool) {
        animationToken += 1
        let currentToken = animationToken
        if reduceMotion {
            showMainTabs = !isActive
            showSettingsTabs = isActive
            return
        }

        let spinAmount = Double(gearTravelDistance) * gearRotationPerPoint
        let fadeAnimation = tabFadeAnimation

        if isActive {
            withAnimation(fadeAnimation) {
                showMainTabs = false
            }
            withAnimation(.easeInOut(duration: gearSpinDuration)) {
                gearSpinDegrees -= spinAmount
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + gearSlideDuration) {
                guard animationToken == currentToken else { return }
                withAnimation(fadeAnimation) {
                    showSettingsTabs = true
                }
            }
        } else {
            withAnimation(fadeAnimation) {
                showSettingsTabs = false
            }
            withAnimation(.easeInOut(duration: gearSpinDuration)) {
                gearSpinDegrees += spinAmount
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + gearSlideDuration) {
                guard animationToken == currentToken else { return }
                withAnimation(fadeAnimation) {
                    showMainTabs = true
                }
            }
        }
    }

    private var gearRotationPerPoint: Double {
        let circumference = Double.pi * Double(buttonSize)
        guard circumference > 0 else { return 0 }
        return 360.0 / circumference
    }

    private func updateGearTravelDistance(mainFrame: CGRect, settingsFrame: CGRect) {
        let distance = abs(settingsFrame.midX - mainFrame.midX)
        if abs(distance - gearTravelDistance) > 0.5 {
            gearTravelDistance = distance
        }
    }

    private func updateGearPosition(to frame: CGRect) {
        if reduceMotion {
            gearPositionX = frame.midX
            gearPositionY = frame.midY
        } else {
            withAnimation(.spring(response: gearSlideDuration, dampingFraction: 0.85)) {
                gearPositionX = frame.midX
                gearPositionY = frame.midY
            }
        }
    }
}

private struct GlassButtonStyleModifier: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.buttonStyle(PlainButtonStyle())
        } else if #available(macOS 26.0, *) {
            content.buttonStyle(GlassButtonStyle())
        } else {
            content.buttonStyle(PlainButtonStyle())
        }
    }
}

private struct GlassEffectModifier: ViewModifier {
    let isEnabled: Bool
    let cornerRadius: CGFloat
    let fallbackFill: Color

    func body(content: Content) -> some View {
        if isEnabled, #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fallbackFill)
                )
        }
    }
}

/// Slide-over panels that can appear in the drawer
enum DrawerPanel {
    case tapHold            // Tap & Hold configuration (Apple-style 80/20 design)
    case launcherSettings   // Launcher activation mode & history suggestions

    var title: String {
        switch self {
        case .tapHold: "Tap & Hold"
        case .launcherSettings: "Launcher Settings"
        }
    }
}

enum InspectorSection: String {
    case mapper
    case customRules // Only shown when custom rules exist
    case keyboard
    case layout
    case keycaps
    case sounds
    case launchers
}

extension InspectorSection {
    var isSettingsShelf: Bool {
        switch self {
        case .keycaps, .sounds, .keyboard, .layout:
            true
        case .mapper, .customRules, .launchers:
            false
        }
    }
}

// MARK: - Preview

#Preview("Keys Pressed") {
    LiveKeyboardOverlayView(
        viewModel: {
            let vm = KeyboardVisualizationViewModel()
            vm.pressedKeyCodes = [0, 56, 55] // a, leftshift, leftmeta
            return vm
        }(),
        uiState: LiveKeyboardOverlayUIState(),
        inspectorWidth: 240,
        isMapperAvailable: false,
        kanataViewModel: nil
    )
    .padding(40)
    .frame(width: 700, height: 350)
    .background(Color(white: 0.3))
}

#Preview("No Keys") {
    LiveKeyboardOverlayView(
        viewModel: KeyboardVisualizationViewModel(),
        uiState: LiveKeyboardOverlayUIState(),
        inspectorWidth: 240,
        isMapperAvailable: false,
        kanataViewModel: nil
    )
    .padding(40)
    .frame(width: 700, height: 350)
    .background(Color(white: 0.3))
}

// MARK: - Mouse move monitor (resets idle on movement/scroll within overlay)

private struct MouseMoveMonitor: NSViewRepresentable {
    let onMove: () -> Void

    func makeNSView(context _: Context) -> TrackingView {
        TrackingView(onMove: onMove)
    }

    func updateNSView(_ nsView: TrackingView, context _: Context) {
        nsView.onMove = onMove
    }

    /// NSView subclass that fires on every mouse move or scroll within its bounds.
    @MainActor
    final class TrackingView: NSView {
        var onMove: () -> Void
        private var trackingArea: NSTrackingArea?
        private var scrollMonitor: Any?

        init(onMove: @escaping () -> Void) {
            self.onMove = onMove
            super.init(frame: .zero)
        }

        @MainActor required init?(coder: NSCoder) {
            onMove = {}
            super.init(coder: coder)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag, .mouseEnteredAndExited]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true

            // Set up local event monitor for scroll wheel events
            // This catches scroll events anywhere in the window (including the drawer)
            if scrollMonitor == nil {
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    // Check if the scroll event is within our window
                    if event.window == self?.window {
                        self?.onMove()
                    }
                    return event
                }
            }
        }

        override func removeFromSuperview() {
            // Clean up scroll monitor when view is removed
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
            super.removeFromSuperview()
        }

        override func mouseMoved(with _: NSEvent) {
            onMove()
        }

        override func mouseEntered(with _: NSEvent) {
            onMove()
        }

        override func mouseExited(with _: NSEvent) {
            onMove()
        }

        override func hitTest(_: NSPoint) -> NSView? {
            // Let events pass through to the SwiftUI content while still receiving mouseMoved.
            nil
        }
    }
}

// MARK: - Tap-Hold Mini Keycap

/// Small keycap for tap-hold configuration in the customize panel
private struct TapHoldMiniKeycap: View {
    let label: String
    let isRecording: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    private let size: CGFloat = 48
    private let cornerRadius: CGFloat = 8
    private let fontSize: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .shadow(color: shadowColor, radius: shadowRadius, y: shadowOffset)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: isRecording ? 2 : 1)
                )

            if isRecording {
                Text("...")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
            } else if label.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: fontSize * 0.7, weight: .light))
                    .foregroundStyle(foregroundColor.opacity(0.4))
            } else {
                Text(label)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
            onTap()
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var foregroundColor: Color {
        isDark
            ? Color(red: 0.88, green: 0.93, blue: 1.0).opacity(isPressed ? 1.0 : 0.88)
            : Color.primary.opacity(isPressed ? 1.0 : 0.88)
    }

    private var backgroundColor: Color {
        if isRecording {
            return Color.accentColor
        } else if isHovered {
            return isDark ? Color(white: 0.18) : Color(white: 0.92)
        } else {
            return isDark ? Color(white: 0.12) : Color(white: 0.96)
        }
    }

    private var borderColor: Color {
        if isRecording {
            return Color.accentColor.opacity(0.8)
        } else if isHovered {
            return isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.15)
        } else {
            return isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
        }
    }

    private var shadowColor: Color {
        isDark ? Color.black.opacity(0.5) : Color.black.opacity(0.15)
    }

    private var shadowRadius: CGFloat {
        isPressed ? 1 : 2
    }

    private var shadowOffset: CGFloat {
        isPressed ? 1 : 2
    }
}
