import SwiftUI

// MARK: - Layout Handlers

extension View {
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

extension View {
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

extension View {
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
