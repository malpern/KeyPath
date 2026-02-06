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
            if isOpen {
                // When drawer opens, select appropriate default tab
                if !isSettingsShelfActive {
                    if hasCustomRules {
                        // Rules tab is default when rules exist
                        inspectorSection = .customRules
                    } else {
                        // Otherwise default to mapper
                        inspectorSection = .mapper
                    }
                }
                // Load launcher mappings if that's the active section
                if inspectorSection == .launchers {
                    viewModel.loadLauncherMappings()
                }
            } else {
                // Clear selected key and hovered rule key when closing
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
        // Switch to Mapper tab when a key is clicked while in Rules tab
        // Re-post notification after tab switch so mapper section receives it after mounting
        content = AnyView(content.onReceive(NotificationCenter.default.publisher(for: .mapperDrawerKeySelected)) { notification in
            if inspectorSection == .customRules {
                inspectorSection = .mapper
                // Re-post notification after a small delay to allow mapper to mount
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
                            // Clear any selected key to avoid confusion between selection and hover
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
            guard let manager = kanataViewModel?.underlyingManager else { return }

            // Clear all global custom rules atomically (uses clearAllCustomRules which saves to disk)
            await manager.clearAllCustomRules()

            // Remove all app-specific keymaps
            let keymapsToRemove = appKeymaps
            for keymap in keymapsToRemove {
                try? await AppKeymapStore.shared.removeKeymap(bundleIdentifier: keymap.mapping.bundleIdentifier)
            }

            // Regenerate app config and restart Kanata to apply all changes
            do {
                try await AppConfigGenerator.regenerateFromStore()
                await AppContextService.shared.reloadMappings()
                _ = await manager.restartKanata(reason: "All custom rules reset")
            } catch {
                AppLogger.shared.log("⚠️ [LiveKeyboardOverlay] Failed to regenerate config after reset: \(error)")
            }

            // Reload UI state
            loadCustomRulesState()
            SoundPlayer.shared.playSuccessSound()
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
