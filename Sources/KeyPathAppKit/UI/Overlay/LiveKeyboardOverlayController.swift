import AppKit
import Combine
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

// Controls the floating live keyboard overlay window.
// Creates an always-on-top borderless window that shows the live keyboard state.
// Uses CGEvent tap for reliable key detection (same as "See Keymap" feature).

@MainActor
final class LiveKeyboardOverlayController: NSObject, NSWindowDelegate {
    var window: NSWindow?
    let viewModel = KeyboardVisualizationViewModel()
    let uiState = LiveKeyboardOverlayUIState()
    private var hasAutoHiddenForCurrentSettingsSession = false
    private var wasVisibleBeforeAutoHide = false
    var collapsedFrameBeforeInspector: NSRect?
    var lastWindowFrame: NSRect?
    var isAdjustingHeight = false
    var isAdjustingWidth = false
    var isUserResizing = false
    var inspectorAnimationToken = UUID()
    var resizeAnchor: OverlayResizeAnchor = .none
    var resizeStartMouse: NSPoint = .zero
    var resizeStartFrame: NSRect = .zero
    var inspectorDebugLastLog: CFTimeInterval = 0
    var cancellables = Set<AnyCancellable>()
    private var healthObserver: OverlayHealthIndicatorObserver?
    private weak var hostingView: NSHostingView<AnyView>?
    private let frameStore = OverlayWindowFrameStore()
    var hintWindowController: HideHintWindowController?
    var hintBubbleObserver: AnyCancellable?

    /// Reference to KanataViewModel for opening Mapper window
    private weak var kanataViewModel: KanataViewModel?

    /// Reference to RuleCollectionsManager for keymap changes
    private weak var ruleCollectionsManager: RuleCollectionsManager?

    // MARK: - UserDefaults Keys

    private enum DefaultsKey {
        static let isVisible = "LiveKeyboardOverlay.isVisible"
        static let userExplicitlyHidden = "LiveKeyboardOverlay.userExplicitlyHidden"
    }

    /// Track if user explicitly hid the overlay via toggle (Cmd+Opt+K or menu)
    /// When true, we won't auto-show on app activation
    private var userExplicitlyHidden: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.userExplicitlyHidden) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.userExplicitlyHidden) }
    }

    let inspectorPanelWidth: CGFloat = 240
    let inspectorAnimationDuration: TimeInterval = 0.35
    let minKeyboardHeight: CGFloat = 180

    /// Get the currently selected physical keyboard layout from UserDefaults
    private var activeLayout: PhysicalLayout {
        let layoutId = UserDefaults.standard.string(forKey: LayoutPreferences.layoutIdKey) ?? LayoutPreferences.defaultLayoutId
        return PhysicalLayout.find(id: layoutId) ?? .macBookUS
    }

    /// Keyboard aspect ratio based on the currently selected layout
    private var currentKeyboardAspectRatio: CGFloat {
        CGFloat(activeLayout.totalWidth / activeLayout.totalHeight)
    }

    private let minInspectorKeyboardHeight: CGFloat = 220
    var inspectorTotalWidth: CGFloat {
        inspectorPanelWidth + OverlayLayoutMetrics.inspectorSeamWidth
    }

    var inspectorDebugEnabled: Bool {
        UserDefaults.standard.bool(forKey: "OverlayInspectorDebug")
    }

    /// Timer for smooth inspector reveal animation (windowDidResize doesn't fire continuously)
    var inspectorAnimationTimer: Timer?

    private var minWindowHeight: CGFloat {
        OverlayLayoutMetrics.verticalChrome + minKeyboardHeight
    }

    private var minWindowWidth: CGFloat {
        let keyboardWidth = minKeyboardHeight * currentKeyboardAspectRatio
        return keyboardWidth
            + OverlayLayoutMetrics.keyboardPadding
            + OverlayLayoutMetrics.keyboardTrailingPadding
            + OverlayLayoutMetrics.outerHorizontalPadding * 2
    }

    /// Shared instance for app-wide access
    static let shared = LiveKeyboardOverlayController()

    private enum LayerChangeSource: String {
        case push
        case kanata
        case unknown
    }

    private let oneShotOverride = OneShotLayerOverrideState(
        timeoutNanoseconds: LiveKeyboardOverlayController.oneShotTimeoutNanoseconds
    )
    private var isLauncherSessionActive = false
    private var shouldRestoreAppHidden = false
    private var shouldRestoreOverlayHidden = false

    override private init() {
        super.init()
        checkBuildVersionAndClearCacheIfNeeded()
        setupLayerChangeObserver()
        setupKeyInputObserver()
        setupOpenOverlayWithMapperObserver()
    }

    /// Check if build changed and clear stale caches
    /// This prevents showing outdated layer mappings after deploying a new build
    /// Uses git commit + build date for uniqueness since CFBundleVersion is static
    private func checkBuildVersionAndClearCacheIfNeeded() {
        let buildInfo = BuildInfo.current()
        // Use git commit + build date as unique identifier (CFBundleVersion is always "0")
        let currentBuild = "\(buildInfo.git)_\(buildInfo.date)"
        let lastBuildKey = "LiveKeyboardOverlay.lastBuildIdentifier"
        let lastBuild = UserDefaults.standard.string(forKey: lastBuildKey)

        if lastBuild != currentBuild {
            AppLogger.shared.info("🔄 [OverlayController] Build changed: \(lastBuild ?? "none") -> \(currentBuild)")
            AppLogger.shared.info("🗑️ [OverlayController] Clearing layer mapping cache to prevent stale data")

            // Clear LayerKeyMapper cache to prevent showing old collection colors/mappings
            viewModel.invalidateLayerMappings()

            // Store new build identifier
            UserDefaults.standard.set(currentBuild, forKey: lastBuildKey)
        } else {
            AppLogger.shared.debug("✅ [OverlayController] Build unchanged: \(currentBuild)")
        }
    }

    private func setupOpenOverlayWithMapperObserver() {
        NotificationCenter.default.addObserver(
            forName: .openOverlayWithMapper,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openWithMapperTab()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openOverlayWithMapperPreset,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract sendable values before entering Task to avoid data race
            let inputKey = notification.userInfo?["inputKey"] as? String
            let outputKey = notification.userInfo?["outputKey"] as? String
            let appBundleId = notification.userInfo?["appBundleId"] as? String
            let appDisplayName = notification.userInfo?["appDisplayName"] as? String
            Task { @MainActor in
                self?.openWithMapperTabAndPreset(
                    inputKey: inputKey,
                    outputKey: outputKey,
                    appBundleId: appBundleId,
                    appDisplayName: appDisplayName
                )
            }
        }
    }

    /// Opens the overlay centered on screen with drawer open and mapper tab selected
    @MainActor
    func openWithMapperTab() {
        // Close settings window if open
        for window in NSApp.windows where window.title == "KeyPath Settings" {
            window.close()
        }

        // Center the window on screen
        showResetCentered()

        // Open inspector with mapper tab
        openInspector(animated: true)

        // Post notification for view to switch to mapper tab
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .switchToMapperTab, object: nil)
        }
    }

    /// Opens the overlay centered on screen with drawer open, mapper tab selected, and preset values
    @MainActor
    func openWithMapperTabAndPreset(
        inputKey: String?,
        outputKey: String?,
        appBundleId: String?,
        appDisplayName: String?
    ) {
        // Close settings window if open
        for window in NSApp.windows where window.title == "KeyPath Settings" {
            window.close()
        }

        // Center the window on screen
        showResetCentered()

        // Open inspector with mapper tab
        openInspector(animated: true)

        // Post notification for view to switch to mapper tab with preset values
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            var notificationUserInfo: [String: Any] = [:]
            if let inputKey {
                notificationUserInfo["inputKey"] = inputKey
            }
            if let outputKey {
                notificationUserInfo["outputKey"] = outputKey
            }
            if let appBundleId {
                notificationUserInfo["appBundleId"] = appBundleId
            }
            if let appDisplayName {
                notificationUserInfo["appDisplayName"] = appDisplayName
            }
            NotificationCenter.default.post(
                name: .switchToMapperTab,
                object: nil,
                userInfo: notificationUserInfo.isEmpty ? nil : notificationUserInfo
            )
        }
    }

    // MARK: - Layer State

    /// Update the current layer name displayed on the overlay
    func updateLayerName(_ layerName: String) {
        viewModel.updateLayer(layerName)
    }

    /// Current layer name shown by the overlay
    var currentLayerName: String {
        viewModel.currentLayerName
    }

    /// Look up the current layer mapping for a key code, if available.
    func lookupCurrentMapping(forKeyCode keyCode: UInt16) -> (layer: String, info: LayerKeyInfo)? {
        guard let info = viewModel.layerKeyMap[keyCode] else {
            return nil
        }
        return (layer: viewModel.currentLayerName, info: info)
    }

    /// Set loading state for layer mapping
    func setLoadingLayerMap(_ isLoading: Bool) {
        viewModel.isLoadingLayerMap = isLoading
    }

    private func setupLayerChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: .kanataLayerChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let layerName = notification.userInfo?["layerName"] as? String else { return }
            let sourceRaw = notification.userInfo?["source"] as? String
            Task { @MainActor in
                guard let self else { return }
                let source = LayerChangeSource(rawValue: sourceRaw ?? "") ?? .unknown
                self.handleLayerChange(layerName, source: source)
            }
        }

        // Listen for config changes to rebuild layer mapping
        NotificationCenter.default.addObserver(
            forName: .kanataConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.shared.info("🔔 [OverlayController] Received kanataConfigChanged notification - invalidating layer mappings")
            Task { @MainActor in
                self?.viewModel.invalidateLayerMappings()
            }
        }
    }

    private func setupKeyInputObserver() {
        NotificationCenter.default.addObserver(
            forName: .kanataKeyInput,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let key = notification.userInfo?["key"] as? String
            let action = notification.userInfo?["action"] as? String
            Task { @MainActor in
                guard let self else { return }
                guard let key, action == "press" else { return }

                // Clear one-shot override on the first non-modifier key press.
                if let overrideLayer = self.oneShotOverride.clearOnKeyPress(
                    key,
                    modifierKeys: Self.modifierKeys
                ) {
                    AppLogger.shared.debug(
                        "🧭 [OverlayController] Clearing one-shot layer override '\(overrideLayer)' on key press: \(key)"
                    )
                }
            }
        }
    }

    private func handleLayerChange(_ layerName: String, source: LayerChangeSource) {
        let normalized = layerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        handleLauncherLayerTransition(normalizedLayer: normalized)

        switch source {
        case .push:
            if normalized == "base" {
                oneShotOverride.clear()
            } else {
                oneShotOverride.activate(normalized)
            }
            updateLayerName(layerName)
        case .kanata:
            // Always honor Kanata's "base" layer change — it means the layer definitively
            // returned to base (one-shot consumed, hold released, etc.). Clear any one-shot
            // override that may be blocking the update. This handles the case where
            // one-shot-press layers don't fire an exit fake key (no push-msg "layer:base").
            if normalized == "base" {
                oneShotOverride.clear()
            } else if oneShotOverride.shouldIgnoreKanataUpdate(normalizedLayer: normalized),
                      let overrideLayer = oneShotOverride.currentLayer
            {
                AppLogger.shared.debug(
                    "🧭 [OverlayController] Ignoring kanata layer '\(layerName)' while one-shot override '\(overrideLayer)' active"
                )
                return
            }
            updateLayerName(layerName)
        case .unknown:
            updateLayerName(layerName)
        }
    }

    private static let modifierKeys: Set<String> = [
        "leftshift",
        "rightshift",
        "leftalt",
        "rightalt",
        "leftctrl",
        "rightctrl",
        "leftmeta",
        "rightmeta",
        "capslock",
        "fn"
    ]

    private static let oneShotTimeoutNanoseconds: UInt64 = 5_000_000_000

    private func handleLauncherLayerTransition(normalizedLayer: String) {
        if normalizedLayer == "launcher" {
            handleLauncherLayerActivated()
            return
        }

        if isLauncherSessionActive {
            if shouldRestoreAppHidden || shouldRestoreOverlayHidden {
                AppLogger.shared.debug(
                    "🪟 [OverlayController] Launcher exited without action - clearing pending restore"
                )
            }
            isLauncherSessionActive = false
            shouldRestoreAppHidden = false
            shouldRestoreOverlayHidden = false
        }
    }

    private func handleLauncherLayerActivated() {
        guard !isLauncherSessionActive else { return }
        isLauncherSessionActive = true

        let appWasHidden = NSApp.isHidden
        let overlayWasHidden = !isVisible
        shouldRestoreAppHidden = appWasHidden
        shouldRestoreOverlayHidden = overlayWasHidden

        guard appWasHidden || overlayWasHidden else { return }

        AppLogger.shared.log(
            "🪟 [OverlayController] Launcher activated while hidden (app=\(appWasHidden), overlay=\(overlayWasHidden)) - bringing to front"
        )

        if appWasHidden {
            NSApp.unhide(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Launcher activation always bypasses hidden check - user is actively using it
        showForQuickLaunch(bypassHiddenCheck: true)
    }

    func noteLauncherActionDispatched() {
        guard shouldRestoreAppHidden || shouldRestoreOverlayHidden else { return }
        let restoreAppHidden = shouldRestoreAppHidden
        let restoreOverlayHidden = shouldRestoreOverlayHidden
        shouldRestoreAppHidden = false
        shouldRestoreOverlayHidden = false
        isLauncherSessionActive = false

        AppLogger.shared.log(
            "🪟 [OverlayController] Restoring hidden state after launcher action (app=\(restoreAppHidden), overlay=\(restoreOverlayHidden))"
        )

        if restoreOverlayHidden {
            isVisible = false
        }
        if restoreAppHidden {
            NSApp.hide(nil)
        }
    }

    private func bringOverlayToFront() {
        if !isVisible {
            isVisible = true
        }
        NSApp.activate(ignoringOtherApps: true)
        // Use orderFront instead of makeKeyAndOrderFront since overlay can't become key
        window?.orderFront(nil)
    }

    /// Restore overlay state from previous session
    /// Only restores if system status is healthy (Kanata running)
    func restoreState() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.isVisible) else { return }

        // Only restore if system is healthy
        Task { @MainActor in
            let health = await ServiceHealthChecker.shared.checkKanataServiceHealth()
            if health.isRunning {
                isVisible = true
            } else {
                AppLogger.shared.log("⚠️ [OverlayController] Skipping overlay restore - Kanata not running")
            }
        }
    }

    // MARK: - Startup Flow

    /// Show overlay for app startup with 30% larger size, centered at bottom with margin.
    /// Also starts health state observation to show validation progress.
    /// - Parameter bypassHiddenCheck: If true, shows overlay even if user explicitly hid it.
    ///   Only use this for the initial app launch, not for subsequent activations.
    func showForStartup(bypassHiddenCheck: Bool = false) {
        // IMPORTANT: Respect user's explicit hide unless bypassed (initial launch only)
        if !bypassHiddenCheck, userExplicitlyHidden {
            AppLogger.shared.log("⏸️ [OverlayController] showForStartup skipped - user explicitly hid overlay")
            return
        }

        // Start health observation and refresh state from current values.
        // Don't manually set .checking - let the observer determine state based on
        // MainAppStateController's current validation state. This fixes the bug where
        // calling showForStartup() multiple times would leave UI stuck in .checking
        // because the observer guard prevents re-subscription and Combine doesn't re-emit.
        observeHealthState()
        healthObserver?.refresh()

        // Create window if needed
        if window == nil {
            createWindow()
        }

        // Calculate 30% larger size using layout constants
        let startupSize = OverlaySizingDefaults.startupSize(
            aspectRatio: currentKeyboardAspectRatio,
            inspectorWidth: inspectorPanelWidth
        )
        let bottomMargin = OverlaySizingDefaults.startupBottomMargin

        // Position: centered horizontally, bottom of screen with margin
        guard let screen = NSScreen.main else {
            // Fallback to regular show if no screen
            showWindow()
            return
        }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - (startupSize.width / 2)
        let y = screenFrame.minY + bottomMargin

        let startupFrame = NSRect(x: x, y: y, width: startupSize.width, height: startupSize.height)
        window?.setFrame(startupFrame, display: true)

        viewModel.startCapturing()
        viewModel.noteInteraction()
        window?.orderFront(nil)

        // Show hint bubble if user hasn't learned the shortcut yet
        if FeatureTipManager.shared.shouldShow(.hideOverlayShortcut) {
            showHintBubbleAfterHealthIndicator()
        }

        AppLogger.shared.log("🚀 [OverlayController] Showing overlay for startup - size: \(Int(startupSize.width))x\(Int(startupSize.height)), position: centered bottom")
    }

    /// Bring the overlay window to the front without changing visibility state
    func bringToFront() {
        window?.orderFrontRegardless()
    }

    /// Show the overlay for a launcher activation while preserving size and position.
    /// - Parameter bypassHiddenCheck: If true, shows overlay even if user explicitly hid it.
    ///   Used for launcher layer activation which should always show the overlay temporarily.
    func showForQuickLaunch(bypassHiddenCheck: Bool = false) {
        // IMPORTANT: Respect user's explicit hide unless bypassed
        // Launcher activation should bypass because user is actively using it
        if !bypassHiddenCheck, userExplicitlyHidden {
            AppLogger.shared.log("⏸️ [OverlayController] showForQuickLaunch skipped - user explicitly hid overlay")
            return
        }

        if window == nil {
            createWindow()
        }

        viewModel.startCapturing()
        viewModel.noteInteraction()

        if let savedFrame = restoreWindowFrame(), let window {
            window.setFrame(savedFrame, display: false)
        }

        window?.orderFront(nil)
        AppLogger.shared.log("🚀 [OverlayController] Showing overlay for launcher activation")
    }

    /// Observe MainAppStateController for health state changes
    private func observeHealthState() {
        if healthObserver == nil {
            healthObserver = OverlayHealthIndicatorObserver(
                onStateChange: { [weak self] state in
                    self?.uiState.healthIndicatorState = state
                },
                onDismiss: { [weak self] in
                    withAnimation(.easeOut(duration: 0.3)) {
                        self?.uiState.healthIndicatorState = .dismissed
                    }
                }
            )
        }

        healthObserver?.start(
            validationStatePublisher: MainAppStateController.shared.$validationState.eraseToAnyPublisher(),
            issuesPublisher: MainAppStateController.shared.$issues.eraseToAnyPublisher()
        )
    }

    /// Handle tap on health indicator - launches wizard and dismisses indicator
    func handleHealthIndicatorTap() {
        AppLogger.shared.log("🔘 [Controller] handleHealthIndicatorTap - bringing main window to front and opening wizard")

        // Bring the main app window to front first (wizard is a sheet on ContentView)
        NSApp.activate(ignoringOtherApps: true)

        // Find the main window (not the floating overlay)
        if let mainWindow = NSApp.windows.first(where: { !$0.styleMask.contains(.borderless) && $0.level == .normal }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }

        // Post notification to show wizard (handled by ContentView)
        NotificationCenter.default.post(name: .showWizard, object: nil)

        withAnimation {
            uiState.healthIndicatorState = .dismissed
        }
    }

    /// Configure the KanataViewModel reference for opening Mapper from overlay clicks
    func configure(kanataViewModel: KanataViewModel, ruleCollectionsManager: RuleCollectionsManager? = nil) {
        self.kanataViewModel = kanataViewModel
        self.ruleCollectionsManager = ruleCollectionsManager
        refreshOverlayContent()
    }

    /// Show or hide the overlay window
    var isVisible: Bool {
        get { window?.isVisible ?? false }
        set {
            if newValue {
                showWindow()
            } else {
                hideWindow()
            }
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.isVisible)
        }
    }

    /// Toggle overlay visibility
    /// If trying to show and system status is not healthy, launches the wizard instead
    /// - Parameter viaKeyboardShortcut: Set to true when toggled via ⌘⌥K to track learning
    func toggle(viaKeyboardShortcut: Bool = false) {
        if isVisible {
            // User explicitly hiding - mark as such so we don't auto-show on app activation
            userExplicitlyHidden = true

            // Record use of hide shortcut for learning tracking
            if viaKeyboardShortcut {
                FeatureTipManager.shared.recordUse(.hideOverlayShortcut)
                let state = FeatureTipManager.shared.learningState(for: .hideOverlayShortcut)
                AppLogger.shared.log("📚 [OverlayController] Recorded hide shortcut use (\(state.useCount)/\(state.requiredUses))")
            }

            isVisible = false
        } else {
            // User explicitly showing - clear the explicit hide flag
            userExplicitlyHidden = false

            // Record use of show shortcut for learning tracking
            if viaKeyboardShortcut {
                FeatureTipManager.shared.recordUse(.hideOverlayShortcut)
                let state = FeatureTipManager.shared.learningState(for: .hideOverlayShortcut)
                AppLogger.shared.log("📚 [OverlayController] Recorded show shortcut use (\(state.useCount)/\(state.requiredUses))")
            }

            // Showing requires system to be healthy
            Task { @MainActor in
                let health = await ServiceHealthChecker.shared.checkKanataServiceHealth()
                if health.isRunning {
                    isVisible = true
                } else {
                    // System not ready - launch wizard instead
                    AppLogger.shared.log("⚠️ [OverlayController] Cannot show overlay - Kanata not running, launching wizard")
                    NotificationCenter.default.post(name: .showWizard, object: nil)
                }
            }
        }
    }

    /// Check if auto-showing overlay is allowed
    /// Returns false if user explicitly hidden OR if wizard/settings is currently hiding it
    var canAutoShow: Bool {
        !userExplicitlyHidden && !hasAutoHiddenForCurrentSettingsSession
    }

    /// Clear the explicit hide flag (e.g., on fresh app launch)
    func clearExplicitHideFlag() {
        userExplicitlyHidden = false
    }

    /// Reset the overlay window to its default size and position
    func resetWindowFrame() {
        frameStore.clear()

        // If window is currently visible, close and reopen to apply default frame
        if isVisible {
            hideWindow()
            showWindow()
        }

        AppLogger.shared.log("🔧 [OverlayController] Window frame reset to defaults")
    }

    /// Show the overlay, restore its default size, and center it on screen.
    func showResetCentered() {
        frameStore.clear()

        if window == nil {
            createWindow()
        }

        viewModel.startCapturing()
        viewModel.noteInteraction()

        if uiState.isInspectorOpen || uiState.inspectorReveal > 0 {
            closeInspector(animated: false)
        }

        guard let window else { return }

        let frame = defaultCenteredFrame(on: window.screen ?? NSScreen.main)
        let constrained = window.constrainFrameRect(frame, to: window.screen)
        window.setFrame(constrained, display: true, animate: false)
        collapsedFrameBeforeInspector = constrained
        persistWindowFrame(constrained)

        window.orderFront(nil)
        AppLogger.shared.log("🔧 [OverlayController] Window reset to defaults and centered")
    }

    func toggleInspectorPanel() {
        // Ignore toggle during animation to prevent race conditions
        guard !uiState.isInspectorAnimating else {
            AppLogger.shared.log("🔧 [OverlayController] toggleInspectorPanel ignored - animation in progress")
            return
        }
        AppLogger.shared.log("🔧 [OverlayController] toggleInspectorPanel called - isInspectorOpen=\(uiState.isInspectorOpen), reveal=\(uiState.inspectorReveal)")
        if uiState.isInspectorOpen || uiState.inspectorReveal > 0 {
            AppLogger.shared.log("🔧 [OverlayController] Closing inspector...")
            closeInspector(animated: true)
        } else {
            if let window {
                let minInspectorHeight = OverlayLayoutMetrics.verticalChrome + minInspectorKeyboardHeight
                if window.frame.height < minInspectorHeight {
                    // Auto-resize window to minimum height required for inspector
                    // Do this synchronously (no animation) to prevent keyboard movement before drawer opens
                    AppLogger.shared.log("📐 [OverlayController] Auto-resizing window from \(window.frame.height.rounded())pt to \(minInspectorHeight)pt for inspector")
                    var newFrame = window.frame
                    newFrame.size.height = minInspectorHeight
                    // Adjust width to maintain aspect ratio
                    let keyboardHeight = minInspectorHeight - OverlayLayoutMetrics.verticalChrome
                    let keyboardWidth = keyboardHeight * currentKeyboardAspectRatio
                    let horizontalChrome = OverlayLayoutMetrics.keyboardPadding
                        + OverlayLayoutMetrics.keyboardTrailingPadding
                        + OverlayLayoutMetrics.outerHorizontalPadding * 2
                    newFrame.size.width = keyboardWidth + horizontalChrome
                    // Keep top edge anchored (don't move window down) - only adjust if needed to stay on screen
                    let constrained = window.constrainFrameRect(newFrame, to: window.screen)
                    window.setFrame(constrained, display: true, animate: false)
                }
            }
            AppLogger.shared.log("🔧 [OverlayController] Opening inspector...")
            dismissHintBubble()
            openInspector(animated: true)
        }
    }

    /// Toggle the drawer with a brief visual highlight on the button (for hotkey feedback)
    func toggleDrawerWithHighlight() {
        // Briefly highlight the button to show visual feedback
        uiState.drawerButtonHighlighted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.uiState.drawerButtonHighlighted = false
        }

        // Toggle the drawer
        toggleInspectorPanel()
    }

    /// Automatically hide the overlay when Settings/Wizard opens.
    /// Does NOT set userExplicitlyHidden since this is automatic, not user action.
    func autoHideOnceForSettings() {
        guard !hasAutoHiddenForCurrentSettingsSession else { return }
        hasAutoHiddenForCurrentSettingsSession = true
        wasVisibleBeforeAutoHide = isVisible
        if isVisible {
            isVisible = false
        }
    }

    /// Reset the auto-hide guard when Settings/Wizard closes.
    /// Restores the overlay if it was visible before auto-hide.
    func resetSettingsAutoHideGuard() {
        let shouldRestore = wasVisibleBeforeAutoHide
        hasAutoHiddenForCurrentSettingsSession = false
        wasVisibleBeforeAutoHide = false

        // Restore overlay if it was visible before wizard/settings opened
        if shouldRestore, !isVisible {
            isVisible = true
        }
    }

    // MARK: - Window Management

    private func showWindow() {
        if window == nil {
            createWindow()
        }
        viewModel.startCapturing()
        viewModel.noteInteraction() // Reset fade state when showing
        // Restore saved frame to prevent shrinking on hide/show cycle
        if let savedFrame = restoreWindowFrame(), let window {
            var targetFrame = savedFrame
            if uiState.isInspectorOpen || uiState.inspectorReveal > 0 {
                let maxVisibleX = window.screen?.visibleFrame.maxX
                targetFrame = InspectorPanelLayout.expandedFrame(
                    baseFrame: savedFrame,
                    inspectorWidth: inspectorTotalWidth,
                    maxVisibleX: maxVisibleX
                )
                collapsedFrameBeforeInspector = savedFrame
            }
            window.setFrame(targetFrame, display: false)
        }

        // Animate in: start scaled down and transparent, then expand
        if let contentView = window?.contentView {
            contentView.wantsLayer = true
            contentView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            // Adjust position for anchor point change
            let bounds = contentView.bounds
            contentView.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)

            // Start small and transparent
            contentView.layer?.transform = CATransform3DMakeScale(0.95, 0.95, 1.0)
            contentView.alphaValue = 0

            window?.orderFront(nil)

            // Animate to full size
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentView.animator().alphaValue = 1.0
                contentView.layer?.transform = CATransform3DIdentity
            }
        } else {
            window?.orderFront(nil)
        }

        // Show hint bubble if user hasn't learned the shortcut yet
        if FeatureTipManager.shared.shouldShow(.hideOverlayShortcut) {
            showHintBubbleAfterHealthIndicator()
        }

        // Ensure health state reflects current MainAppStateController values.
        // This is a belt-and-suspenders fix for stale "System Not Ready" state.
        observeHealthState()
        healthObserver?.refresh()
    }

    private func hideWindow() {
        // Save frame BEFORE closing inspector (which modifies the frame)
        saveWindowFrame()
        viewModel.stopCapturing()
        dismissHintBubble()

        if uiState.isInspectorOpen || uiState.inspectorReveal > 0 {
            closeInspector(animated: false)
        }

        // Animate out: scale down and fade, then hide
        if let contentView = window?.contentView {
            contentView.wantsLayer = true
            contentView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            // Adjust position for anchor point change
            let bounds = contentView.bounds
            contentView.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                contentView.animator().alphaValue = 0
                contentView.layer?.transform = CATransform3DMakeScale(0.95, 0.95, 1.0)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.window?.orderOut(nil)
                    // Reset for next show
                    contentView.alphaValue = 1.0
                    contentView.layer?.transform = CATransform3DIdentity
                }
            }
        } else {
            window?.orderOut(nil)
        }
    }

    // MARK: - Key Click Handling

    /// Handle keymap selection change - regenerates Kanata config with new layout
    private func handleKeymapChanged(keymapId: String, includePunctuation: Bool) {
        guard let ruleCollectionsManager else {
            AppLogger.shared.log("⚠️ [OverlayController] Cannot apply keymap - RuleCollectionsManager not configured")
            return
        }

        AppLogger.shared.log("⌨️ [OverlayController] Keymap changed to '\(keymapId)' (punctuation: \(includePunctuation))")

        Task { @MainActor in
            let conflicts = await ruleCollectionsManager.setActiveKeymap(keymapId, includePunctuation: includePunctuation)

            if !conflicts.isEmpty {
                // The RuleCollectionsManager already logs and warns via its callback
                AppLogger.shared.log("⚠️ [OverlayController] Keymap change had \(conflicts.count) conflict(s)")
            }
        }
    }

    /// Handle click on a key in the overlay - selects the key in the drawer mapper (when visible)
    private func handleKeyClick(key: PhysicalKey, layerInfo: LayerKeyInfo?) {
        if key.layoutRole == .touchId {
            toggleInspectorPanel()
            return
        }

        guard kanataViewModel != nil else {
            AppLogger.shared.log("⚠️ [OverlayController] Cannot open Mapper - KanataViewModel not configured")
            return
        }

        // Convert key code to kanata name for input label
        let inputKey = OverlayKeyboardView.keyCodeToKanataName(key.keyCode)

        // In launcher mode, treat key clicks as immediate launch actions.
        if viewModel.isLauncherModeActive {
            let normalizedKey = inputKey.lowercased()

            if normalizedKey == "esc" {
                AppLogger.shared.log("🖱️ [OverlayController] Launcher cancel clicked (esc)")
                ActionDispatcher.shared.dispatch(message: "layer:base")
                return
            }

            if let mapping = viewModel.launcherMappings[normalizedKey],
               let message = Self.launcherActionMessage(for: mapping.target)
            {
                AppLogger.shared.log("🖱️ [OverlayController] Launcher key clicked: \(normalizedKey) -> \(message)")
                ActionDispatcher.shared.dispatch(message: message)
                ActionDispatcher.shared.dispatch(message: "layer:base")
                return
            }
        }

        // Get output from layer info
        // For simple key mappings, use outputKey (e.g., "left", "esc")
        // For complex actions (push-msg, app launch), outputKey is nil so use displayLabel
        let outputKey: String = if let simpleOutput = layerInfo?.outputKey {
            simpleOutput
        } else if let displayLabel = layerInfo?.displayLabel, !displayLabel.isEmpty {
            // Complex action - pass displayLabel so Mapper shows what the key does
            displayLabel
        } else {
            // No mapping - key maps to itself
            inputKey
        }

        // Get current layer from the overlay's viewModel
        let currentLayer = viewModel.currentLayerName

        AppLogger.shared.log("🖱️ [OverlayController] Key clicked: \(key.label) (keyCode: \(key.keyCode)) -> \(outputKey) [layer: \(currentLayer)]")

        let inspectorVisible = uiState.isInspectorOpen || uiState.isInspectorAnimating || uiState.inspectorReveal > 0
        guard inspectorVisible else {
            AppLogger.shared.log("🖱️ [OverlayController] Key click ignored (drawer not visible)")
            return
        }

        // Update selected key for visual highlight
        viewModel.selectedKeyCode = key.keyCode

        // Post notification for mapper drawer to update its input
        var userInfo: [String: Any] = [
            "keyCode": key.keyCode,
            "inputKey": inputKey,
            "outputKey": outputKey,
            "layer": currentLayer
        ]
        // Include action identifiers if present
        if let appId = layerInfo?.appLaunchIdentifier {
            userInfo["appIdentifier"] = appId
        }
        if let systemId = layerInfo?.systemActionIdentifier {
            userInfo["systemActionIdentifier"] = systemId
        }
        if let urlId = layerInfo?.urlIdentifier {
            userInfo["urlIdentifier"] = urlId
        }
        NotificationCenter.default.post(
            name: .mapperDrawerKeySelected,
            object: nil,
            userInfo: userInfo
        )
    }

    private static func launcherActionMessage(for target: LauncherTarget) -> String? {
        switch target {
        case let .app(name, bundleId):
            return "launch:\(bundleId ?? name)"
        case let .url(urlString):
            let encoded = URLMappingFormatter.encodeForPushMessage(urlString)
            return "open:\(encoded)"
        case let .folder(path, _):
            return "folder:\(path)"
        case let .script(path, _):
            return "script:\(path)"
        }
    }

    func saveWindowFrame() {
        guard let window else { return }
        let frame = if uiState.isInspectorOpen {
            collapsedFrameBeforeInspector ?? InspectorPanelLayout.collapsedFrame(
                expandedFrame: window.frame,
                inspectorWidth: inspectorTotalWidth
            )
        } else {
            window.frame
        }
        let height = uiState.desiredContentHeight > 0 ? uiState.desiredContentHeight : frame.height
        guard frame.width > 0, height > 0 else { return }
        persistWindowFrame(NSRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: height))
    }

    private func persistWindowFrame(_ frame: NSRect) {
        frameStore.save(frame: frame)
    }

    private func defaultCenteredFrame(on screen: NSScreen?) -> NSRect {
        OverlaySizingDefaults.resetCenteredFrame(
            visibleFrame: screen?.visibleFrame,
            aspectRatio: currentKeyboardAspectRatio,
            inspectorWidth: inspectorPanelWidth
        )
    }

    private func restoreWindowFrame() -> NSRect? {
        frameStore.restore()
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidMove(_: Notification) {
        Task { @MainActor in
            handleWindowFrameChange()
        }
    }

    nonisolated func windowDidResize(_: Notification) {
        Task { @MainActor in
            handleWindowFrameChange()
        }
    }

    func windowWillStartLiveResize(_: Notification) {
        isUserResizing = true
        resizeAnchor = .none
        resizeStartMouse = NSEvent.mouseLocation
        resizeStartFrame = window?.frame ?? .zero
    }

    func windowDidEndLiveResize(_: Notification) {
        isUserResizing = false
        resizeAnchor = .none
        handleWindowFrameChange()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let aspect = max(uiState.keyboardAspectRatio, 0.1)
        let verticalChrome = OverlayLayoutMetrics.verticalChrome
        let horizontalChrome = OverlayLayoutMetrics.horizontalChrome(
            inspectorVisible: uiState.isInspectorOpen,
            inspectorWidth: inspectorPanelWidth
        )
        let minSize = sender.minSize
        let maxSize = sender.maxSize
        let currentSize = sender.frame.size

        let widthDelta = abs(frameSize.width - currentSize.width)
        let heightDelta = abs(frameSize.height - currentSize.height)
        let anchor = resolveResizeAnchor(widthDelta: widthDelta, heightDelta: heightDelta)
        return OverlayWindowResizer.constrainedSize(
            targetSize: frameSize,
            currentSize: currentSize,
            aspect: aspect,
            verticalChrome: verticalChrome,
            horizontalChrome: horizontalChrome,
            minSize: minSize,
            maxSize: maxSize,
            anchor: anchor
        )
    }

    private func createWindow() {
        // Keyboard aspect ratio: totalWidth / totalHeight ≈ 16.45 / 6.5 ≈ 2.53
        // Account for: drag header (15pt) + header spacing, keyboard padding (10pt bottom), top padding, bottom shadow
        // Total chrome ≈ 60pt vertical chrome with current layout constants.
        // Horizontal chrome = 10 (kb padding) * 2 + 4 (outer) * 2 = 28pt
        let keyboardAspectRatio: CGFloat = 2.53
        let verticalChrome: CGFloat = 60
        let horizontalChrome: CGFloat = 28

        // Restore saved frame or calculate from default height
        let savedFrame = restoreWindowFrame()
        let defaultHeight: CGFloat = 220
        let keyboardHeight = defaultHeight - verticalChrome
        let keyboardWidth = keyboardHeight * keyboardAspectRatio
        let defaultWidth = keyboardWidth + horizontalChrome
        let initialSize = savedFrame?.size ?? NSSize(width: defaultWidth, height: defaultHeight)

        let wrappedContent = buildRootView()

        let hostingView = NSHostingView(rootView: wrappedContent)
        hostingView.setFrameSize(initialSize)
        self.hostingView = hostingView

        // Borderless, resizable window
        // In accessibility test mode, use titled window for automation tools like Peekaboo
        let useAccessibilityTestMode = ProcessInfo.processInfo.environment["KEYPATH_ACCESSIBILITY_TEST_MODE"] != nil
        let windowStyle = OverlayWindowFactory.windowStyle(useAccessibilityTestMode: useAccessibilityTestMode)

        let window = OverlayWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: windowStyle,
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.delegate = self

        OverlayWindowFactory.configure(window: window, useAccessibilityTestMode: useAccessibilityTestMode)
        // Prevent the window from ever becoming key window (so it doesn't steal keyboard focus)
        // Note: This relies on OverlayWindow.canBecomeKey returning false

        // Allow resize - constrain to keyboard aspect ratio
        // Max: 500pt height -> keyboard area = 446pt -> width = 446 * 2.53 + 28 = 1156
        window.minSize = NSSize(width: minWindowWidth, height: minWindowHeight)
        window.maxSize = NSSize(width: 1160 + inspectorTotalWidth, height: 500)

        // Restore saved position or default to bottom-right corner
        if let savedFrame {
            window.setFrameOrigin(savedFrame.origin)
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let origin = OverlayWindowFactory.defaultOrigin(
                visibleFrame: screenFrame,
                windowSize: windowFrame.size,
                margin: OverlaySizingDefaults.defaultOriginMargin
            )
            window.setFrameOrigin(origin)
        }

        self.window = window
        observeDesiredContentHeight()
        observeDesiredContentWidth()
        observeKeyboardAspectRatio()
    }

    private func buildRootView() -> AnyView {
        let contentView = LiveKeyboardOverlayView(
            viewModel: viewModel,
            uiState: uiState,
            inspectorWidth: inspectorPanelWidth,
            isMapperAvailable: kanataViewModel != nil,
            kanataViewModel: kanataViewModel,
            onKeyClick: { [weak self] key, layerInfo in
                self?.handleKeyClick(key: key, layerInfo: layerInfo)
            },
            onClose: { [weak self] in
                self?.isVisible = false
            },
            onToggleInspector: { [weak self] in
                self?.toggleInspectorPanel()
            },
            onKeymapChanged: { [weak self] keymapId, includePunctuation in
                self?.handleKeymapChanged(keymapId: keymapId, includePunctuation: includePunctuation)
            },
            onHealthIndicatorTap: { [weak self] in
                self?.handleHealthIndicatorTap()
            }
        )

        return AnyView(contentView)
    }

    private func refreshOverlayContent() {
        guard let hostingView else { return }
        hostingView.rootView = buildRootView()
    }
}
