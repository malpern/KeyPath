import KeyPathCore
import SwiftUI

extension LiveKeyboardOverlayView {
    // MARK: - Overlay Content

    func overlayContent(
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

    func overlayMainContent(
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

            if inspectorVisible, let kbWidth = fixedKeyboardWidth, let kbHeight = fixedKeyboardHeight {
                Rectangle()
                    .fill(Color(white: isDark ? 0.1 : 0.92))
                    .frame(width: kbWidth, height: kbHeight)
                    .padding(.top, headerBottomSpacing)
                    .padding(.leading, keyboardPadding)
            }

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
