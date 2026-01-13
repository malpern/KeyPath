import AppKit
import Combine
import KeyPathCore
import KeyPathWizardCore
import SwiftUI

// MARK: - Health Indicator State

/// State for the system health indicator shown in the overlay header
enum HealthIndicatorState: Equatable {
    case checking
    case healthy
    case unhealthy(issueCount: Int)
    case dismissed
}

/// Controls the floating live keyboard overlay window.
/// Creates an always-on-top borderless window that shows the live keyboard state.
/// Uses CGEvent tap for reliable key detection (same as "See Keymap" feature).

@MainActor
final class LiveKeyboardOverlayController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let viewModel = KeyboardVisualizationViewModel()
    private let uiState = LiveKeyboardOverlayUIState()
    private var hasAutoHiddenForCurrentSettingsSession = false
    private var collapsedFrameBeforeInspector: NSRect?
    private var lastWindowFrame: NSRect?
    private var isAdjustingHeight = false
    private var isAdjustingWidth = false
    private var isUserResizing = false
    private var inspectorAnimationToken = UUID()
    private var resizeAnchor: OverlayResizeAnchor = .none
    private var resizeStartMouse: NSPoint = .zero
    private var resizeStartFrame: NSRect = .zero
    private var inspectorDebugLastLog: CFTimeInterval = 0
    private var cancellables = Set<AnyCancellable>()
    private var healthObserver: OverlayHealthIndicatorObserver?
    private weak var hostingView: NSHostingView<AnyView>?
    private let frameStore = OverlayWindowFrameStore()

    /// Timestamp when overlay was auto-hidden for settings (for restore on close)
    private var autoHiddenTimestamp: Date?

    /// Duration within which we'll restore the overlay when settings closes (10 minutes)
    private let restoreWindowDuration: TimeInterval = 10 * 60

    /// Reference to KanataViewModel for opening Mapper window
    private weak var kanataViewModel: KanataViewModel?

    /// Reference to RuleCollectionsManager for keymap changes
    private weak var ruleCollectionsManager: RuleCollectionsManager?

    // MARK: - UserDefaults Keys

    private enum DefaultsKey {
        static let isVisible = "LiveKeyboardOverlay.isVisible"
    }

    private let inspectorPanelWidth: CGFloat = 240
    private let inspectorAnimationDuration: TimeInterval = 0.35
    private let minKeyboardHeight: CGFloat = 180

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
    private var inspectorTotalWidth: CGFloat {
        inspectorPanelWidth + OverlayLayoutMetrics.inspectorSeamWidth
    }

    private var inspectorDebugEnabled: Bool {
        UserDefaults.standard.bool(forKey: "OverlayInspectorDebug")
    }

    /// Timer for smooth inspector reveal animation (windowDidResize doesn't fire continuously)
    private var inspectorAnimationTimer: Timer?

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
        resetWindowFrame()

        // Show the overlay
        showWindow()

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
        resetWindowFrame()

        // Show the overlay
        showWindow()

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
            if oneShotOverride.shouldIgnoreKanataUpdate(normalizedLayer: normalized),
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
        showForQuickLaunch()
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
        window?.makeKeyAndOrderFront(nil)
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
    func showForStartup() {
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

        AppLogger.shared.log("🚀 [OverlayController] Showing overlay for startup - size: \(Int(startupSize.width))x\(Int(startupSize.height)), position: centered bottom")
    }

    /// Bring the overlay window to the front without changing visibility state
    func bringToFront() {
        window?.orderFrontRegardless()
    }

    /// Show the overlay for a launcher activation while preserving size and position.
    func showForQuickLaunch() {
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
    func toggle() {
        if isVisible {
            // Hiding is always allowed
            isVisible = false
        } else {
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

    /// Automatically hide the overlay once when Settings opens.
    /// If the user later shows it manually, we won't hide it again until Settings closes.
    func autoHideOnceForSettings() {
        guard !hasAutoHiddenForCurrentSettingsSession else { return }
        hasAutoHiddenForCurrentSettingsSession = true
        if isVisible {
            autoHiddenTimestamp = Date()
            isVisible = false
        }
    }

    /// Reset the one-shot auto-hide guard when Settings closes.
    /// Restores the overlay if it was auto-hidden within the restore window (10 minutes).
    func resetSettingsAutoHideGuard() {
        defer {
            hasAutoHiddenForCurrentSettingsSession = false
            autoHiddenTimestamp = nil
        }

        // Restore overlay if it was auto-hidden recently and user hasn't manually shown it
        if let hiddenAt = autoHiddenTimestamp,
           Date().timeIntervalSince(hiddenAt) < restoreWindowDuration,
           !isVisible
        {
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
            window.setFrame(savedFrame, display: false)
        }
        window?.orderFront(nil)

        // Ensure health state reflects current MainAppStateController values.
        // This is a belt-and-suspenders fix for stale "System Not Ready" state.
        observeHealthState()
        healthObserver?.refresh()
    }

    private func hideWindow() {
        // Save frame BEFORE closing inspector (which modifies the frame)
        saveWindowFrame()
        viewModel.stopCapturing()
        if uiState.isInspectorOpen || uiState.inspectorReveal > 0 {
            closeInspector(animated: false)
        }
        window?.orderOut(nil)
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
            "launch:\(bundleId ?? name)"
        case let .url(urlString):
            "open:\(urlString)"
        case let .folder(path, _):
            "folder:\(path)"
        case let .script(path, _):
            "script:\(path)"
        }
    }

    private func saveWindowFrame() {
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

    // MARK: - Inspector Panel

    private func openInspector(animated: Bool) {
        guard let window else { return }
        let token = UUID()
        inspectorAnimationToken = token
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let baseFrame = window.frame
        collapsedFrameBeforeInspector = baseFrame

        let maxVisibleX = window.screen?.visibleFrame.maxX
        let expandedFrame = InspectorPanelLayout.expandedFrame(
            baseFrame: baseFrame,
            inspectorWidth: inspectorTotalWidth,
            maxVisibleX: maxVisibleX
        )

        if inspectorDebugEnabled {
            AppLogger.shared.log(
                "📤 [OverlayInspector] open start frame=\(baseFrame.debugDescription) " +
                    "expanded=\(expandedFrame.debugDescription) totalW=\(inspectorTotalWidth.rounded())"
            )
        }

        uiState.isInspectorClosing = false
        uiState.isInspectorAnimating = shouldAnimate

        if shouldAnimate {
            animateInspectorReveal(to: 1)
            setWindowFrame(expandedFrame, animated: true, duration: inspectorAnimationDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + inspectorAnimationDuration) { [weak self] in
                guard let self, inspectorAnimationToken == token else { return }
                finalizeInspectorAnimation()
                uiState.isInspectorOpen = true
                uiState.inspectorReveal = 1
                lastWindowFrame = expandedFrame
                if inspectorDebugEnabled {
                    AppLogger.shared.log(
                        "📤 [OverlayInspector] open end frame=\(expandedFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                    )
                }
            }
        } else {
            uiState.inspectorReveal = 1
            setWindowFrame(expandedFrame, animated: false)
            uiState.isInspectorOpen = true
            uiState.isInspectorAnimating = false
            lastWindowFrame = expandedFrame
            if inspectorDebugEnabled {
                AppLogger.shared.log(
                    "📤 [OverlayInspector] open instant frame=\(expandedFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                )
            }
        }
    }

    private func closeInspector(animated: Bool) {
        guard let window else { return }
        guard uiState.isInspectorOpen || uiState.inspectorReveal > 0 || uiState.isInspectorAnimating else {
            uiState.isInspectorClosing = false
            return
        }
        let targetFrame = collapsedFrameBeforeInspector ?? InspectorPanelLayout.collapsedFrame(
            expandedFrame: window.frame,
            inspectorWidth: inspectorTotalWidth
        )
        let token = UUID()
        inspectorAnimationToken = token
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if inspectorDebugEnabled {
            AppLogger.shared.log(
                "📥 [OverlayInspector] close start frame=\(window.frame.debugDescription) " +
                    "target=\(targetFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
            )
        }

        uiState.isInspectorAnimating = shouldAnimate
        uiState.isInspectorClosing = shouldAnimate

        if shouldAnimate {
            animateInspectorReveal(to: 0)
            setWindowFrame(targetFrame, animated: true, duration: inspectorAnimationDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + inspectorAnimationDuration) { [weak self] in
                guard let self, inspectorAnimationToken == token else { return }
                finalizeInspectorAnimation()
                uiState.inspectorReveal = 0
                uiState.isInspectorOpen = false
                uiState.isInspectorClosing = false
                collapsedFrameBeforeInspector = nil
                lastWindowFrame = targetFrame
                if inspectorDebugEnabled {
                    AppLogger.shared.log(
                        "📥 [OverlayInspector] close end frame=\(targetFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                    )
                }
            }
        } else {
            setWindowFrame(targetFrame, animated: false)
            uiState.inspectorReveal = 0
            uiState.isInspectorOpen = false
            uiState.isInspectorAnimating = false
            uiState.isInspectorClosing = false
            collapsedFrameBeforeInspector = nil
            lastWindowFrame = targetFrame
            if inspectorDebugEnabled {
                AppLogger.shared.log(
                    "📥 [OverlayInspector] close instant frame=\(targetFrame.debugDescription) reveal=\(uiState.inspectorReveal)"
                )
            }
        }
    }

    /// Animate inspector reveal from current value to target (0 or 1)
    private func animateInspectorReveal(to targetReveal: CGFloat) {
        let startTime = CACurrentMediaTime()
        let startReveal = uiState.inspectorReveal
        inspectorAnimationTimer?.invalidate()
        inspectorAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            Task { @MainActor in
                let elapsed = CACurrentMediaTime() - startTime
                let progress = min(1.0, elapsed / inspectorAnimationDuration)
                uiState.inspectorReveal = OverlayInspectorMath.revealValue(
                    start: startReveal,
                    target: targetReveal,
                    elapsed: elapsed,
                    duration: inspectorAnimationDuration
                )

                if progress >= 1.0 {
                    inspectorAnimationTimer?.invalidate()
                    inspectorAnimationTimer = nil
                }
            }
        }
    }

    /// Clean up animation state after completion
    private func finalizeInspectorAnimation() {
        inspectorAnimationTimer?.invalidate()
        inspectorAnimationTimer = nil
        uiState.isInspectorAnimating = false
    }

    private func handleWindowFrameChange() {
        guard let window else { return }
        if uiState.isInspectorOpen, !uiState.isInspectorClosing {
            updateCollapsedFrame(forExpandedFrame: window.frame)
        }
        if uiState.isInspectorAnimating {
            updateInspectorRevealFromWindow()
            if inspectorDebugEnabled {
                let now = CFAbsoluteTimeGetCurrent()
                if now - inspectorDebugLastLog > 0.2 {
                    inspectorDebugLastLog = now
                    let revealStr = String(format: "%.3f", uiState.inspectorReveal)
                    AppLogger.shared.log(
                        "🪟 [OverlayInspector] frame=\(window.frame.debugDescription) " +
                            "reveal=\(revealStr) " +
                            "animating=\(uiState.isInspectorAnimating) closing=\(uiState.isInspectorClosing)"
                    )
                }
            }
            return
        }
        saveWindowFrame()
        lastWindowFrame = window.frame
    }

    private func updateInspectorRevealFromWindow() {
        guard let window else { return }
        let collapsedWidth = collapsedFrameBeforeInspector?.width ?? max(0, window.frame.width - inspectorTotalWidth)
        uiState.inspectorReveal = OverlayInspectorMath.clampedReveal(
            expandedWidth: window.frame.width,
            collapsedWidth: collapsedWidth,
            inspectorWidth: inspectorTotalWidth
        )
    }

    private func updateCollapsedFrame(forExpandedFrame expandedFrame: NSRect) {
        var baseFrame = collapsedFrameBeforeInspector ?? expandedFrame
        if let lastFrame = lastWindowFrame {
            let deltaX = expandedFrame.origin.x - lastFrame.origin.x
            let deltaY = expandedFrame.origin.y - lastFrame.origin.y
            baseFrame.origin.x += deltaX
            baseFrame.origin.y += deltaY
        } else {
            baseFrame.origin = expandedFrame.origin
        }
        baseFrame.size.width = max(0, expandedFrame.width - inspectorTotalWidth)
        baseFrame.size.height = expandedFrame.height
        collapsedFrameBeforeInspector = baseFrame
    }

    private func setWindowFrame(_ frame: NSRect, animated: Bool, duration: TimeInterval? = nil) {
        guard let window else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration ?? inspectorAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    private func observeDesiredContentHeight() {
        uiState.$desiredContentHeight
            .removeDuplicates()
            .sink { [weak self] height in
                guard let self, !self.isUserResizing else { return }
                applyDesiredContentHeight(height)
            }
            .store(in: &cancellables)
    }

    private func observeDesiredContentWidth() {
        uiState.$desiredContentWidth
            .removeDuplicates()
            .sink { [weak self] width in
                guard let self, !self.isUserResizing else { return }
                applyDesiredContentWidth(width)
            }
            .store(in: &cancellables)
    }

    private func observeKeyboardAspectRatio() {
        uiState.$keyboardAspectRatio
            .removeDuplicates()
            .sink { [weak self] newAspectRatio in
                guard let self, !self.isUserResizing else { return }
                resizeWindowForNewAspectRatio(newAspectRatio)
            }
            .store(in: &cancellables)
    }

    private func resizeWindowForNewAspectRatio(_ newAspectRatio: CGFloat) {
        guard let window else { return }
        guard !isAdjustingHeight, !isAdjustingWidth else { return }

        let verticalChrome = OverlayLayoutMetrics.verticalChrome
        let currentFrame = window.frame

        // Calculate new keyboard width based on new aspect ratio
        // Calculate horizontal chrome (padding + inspector if open)
        let horizontalChrome = OverlayLayoutMetrics.horizontalChrome(
            inspectorVisible: uiState.isInspectorOpen,
            inspectorWidth: inspectorPanelWidth
        )

        let newWindowWidth = OverlayWindowResizer.widthForAspect(
            currentHeight: currentFrame.height,
            aspect: newAspectRatio,
            verticalChrome: verticalChrome,
            horizontalChrome: horizontalChrome
        )

        // Only resize if there's a meaningful difference
        guard abs(currentFrame.width - newWindowWidth) > 1.0 else { return }

        isAdjustingWidth = true
        var newFrame = currentFrame
        newFrame.size.width = newWindowWidth

        // Keep right edge anchored (window moves left as it shrinks, right as it grows)
        newFrame.origin.x = currentFrame.maxX - newWindowWidth

        let constrained = window.constrainFrameRect(newFrame, to: window.screen)
        window.setFrame(constrained, display: true, animate: true)

        isAdjustingWidth = false
    }

    private func applyDesiredContentHeight(_ height: CGFloat) {
        guard let window else { return }
        guard height > 0 else { return }
        guard !isAdjustingHeight else { return }

        let currentFrame = window.frame
        if abs(currentFrame.height - height) < 0.5 {
            return
        }

        isAdjustingHeight = true
        var newFrame = currentFrame
        newFrame.size.height = height
        newFrame.origin.y = currentFrame.maxY - height
        let constrained = window.constrainFrameRect(newFrame, to: window.screen)
        window.setFrame(constrained, display: true, animate: false)
        isAdjustingHeight = false
    }

    private func applyDesiredContentWidth(_ width: CGFloat) {
        guard let window else { return }
        guard width > 0 else { return }
        guard !isAdjustingWidth else { return }
        guard uiState.isInspectorOpen else { return } // Only resize when inspector is open

        let currentFrame = window.frame
        if abs(currentFrame.width - width) < 0.5 {
            return
        }

        isAdjustingWidth = true
        var newFrame = currentFrame
        newFrame.size.width = width
        // Keep right edge anchored (inspector stays in place)
        newFrame.origin.x = currentFrame.maxX - width
        let constrained = window.constrainFrameRect(newFrame, to: window.screen)
        window.setFrame(constrained, display: true, animate: true)
        // Update collapsed frame reference to maintain correct keyboard width
        updateCollapsedFrame(forExpandedFrame: constrained)
        isAdjustingWidth = false
    }

    private func resolveResizeAnchor(widthDelta: CGFloat, heightDelta: CGFloat) -> OverlayResizeAnchor {
        let threshold: CGFloat = 6
        let currentMouse = NSEvent.mouseLocation
        let resolved = OverlayWindowResizer.resolveAnchor(
            existing: resizeAnchor,
            startFrame: resizeStartFrame,
            currentFrame: window?.frame,
            startMouse: resizeStartMouse,
            currentMouse: currentMouse,
            widthDelta: widthDelta,
            heightDelta: heightDelta,
            threshold: threshold
        )
        resizeAnchor = resolved
        return resolved
    }
}

@MainActor
final class LiveKeyboardOverlayUIState: ObservableObject {
    @Published var isInspectorOpen = false
    @Published var inspectorReveal: CGFloat = 0
    @Published var isInspectorAnimating = false
    @Published var isInspectorClosing = false
    @Published var desiredContentHeight: CGFloat = 0
    @Published var desiredContentWidth: CGFloat = 0
    @Published var keyboardAspectRatio: CGFloat = PhysicalLayout.macBookUS.totalWidth / PhysicalLayout.macBookUS.totalHeight

    // Health indicator state for startup validation display
    @Published var healthIndicatorState: HealthIndicatorState = .dismissed

    /// Brief highlight of the drawer button when toggled via hotkey
    @Published var drawerButtonHighlighted = false
}

enum InspectorPanelLayout {
    static func expandedFrame(
        baseFrame: NSRect,
        inspectorWidth: CGFloat,
        maxVisibleX: CGFloat?
    ) -> NSRect {
        var expanded = baseFrame
        expanded.size.width += inspectorWidth

        if let maxVisibleX {
            let overflow = expanded.maxX - maxVisibleX
            if overflow > 0 {
                expanded.origin.x -= overflow
            }
        }

        return expanded
    }

    static func collapsedFrame(expandedFrame: NSRect, inspectorWidth: CGFloat) -> NSRect {
        var collapsed = expandedFrame
        collapsed.size.width = max(0, expandedFrame.width - inspectorWidth)
        return collapsed
    }
}

// MARK: - Overlay Window (allows partial off-screen positioning)

private final class OverlayWindow: NSWindow {
    /// Keep at least this many points visible inside the screen's visibleFrame so the window is recoverable.
    private let minVisible: CGFloat = 30

    /// Prevent the window from becoming key window (so it doesn't steal keyboard focus from other apps)
    override var canBecomeKey: Bool { false }

    /// Prevent the window from becoming main window
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen else { return frameRect }

        let visible = screen.visibleFrame
        var rect = frameRect

        // Horizontal: ensure at least `minVisible` points remain on-screen
        if rect.maxX < visible.minX + minVisible {
            rect.origin.x = visible.minX + minVisible - rect.width
        } else if rect.minX > visible.maxX - minVisible {
            rect.origin.x = visible.maxX - minVisible
        }

        // Vertical: ensure at least `minVisible` points remain on-screen
        if rect.maxY < visible.minY + minVisible {
            rect.origin.y = visible.minY + minVisible - rect.height
        } else if rect.minY > visible.maxY - minVisible {
            rect.origin.y = visible.maxY - minVisible
        }

        return rect
    }
}

@MainActor
final class OneShotLayerOverrideState {
    private(set) var currentLayer: String?
    private var overrideTask: Task<Void, Never>?
    private var overrideToken = UUID()
    private let timeoutNanoseconds: UInt64
    private let sleep: @Sendable (UInt64) async -> Void

    init(
        timeoutNanoseconds: UInt64,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanos in
            try? await Task.sleep(nanoseconds: nanos)
        }
    ) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.sleep = sleep
    }

    func activate(_ layer: String) {
        currentLayer = layer
        scheduleTimeout()
    }

    func clear() {
        currentLayer = nil
        cancelTimeout()
    }

    func clearOnKeyPress(_ key: String, modifierKeys: Set<String>) -> String? {
        guard let layer = currentLayer,
              !modifierKeys.contains(key.lowercased())
        else {
            return nil
        }
        clear()
        return layer
    }

    func shouldIgnoreKanataUpdate(normalizedLayer: String) -> Bool {
        guard let layer = currentLayer else { return false }
        return normalizedLayer != layer
    }

    private func scheduleTimeout() {
        cancelTimeout()
        let token = UUID()
        overrideToken = token
        overrideTask = Task { @MainActor in
            await sleep(timeoutNanoseconds)
            guard overrideToken == token else { return }
            if let layer = currentLayer {
                AppLogger.shared.debug(
                    "🧭 [OverlayController] One-shot override '\(layer)' expired"
                )
                currentLayer = nil
            }
        }
    }

    private func cancelTimeout() {
        overrideTask?.cancel()
        overrideTask = nil
    }
}

// MARK: - Notification Integration

extension Notification.Name {
    /// Posted when the live keyboard overlay should be toggled
    static let toggleLiveKeyboardOverlay = Notification.Name("KeyPath.ToggleLiveKeyboardOverlay")
    /// Posted when the Kanata layer changes (userInfo["layerName"] = String)
    static let kanataLayerChanged = Notification.Name("KeyPath.KanataLayerChanged")
    /// Posted when the Kanata config changes (rules saved, etc.)
    static let kanataConfigChanged = Notification.Name("KeyPath.KanataConfigChanged")
    /// Posted when a TCP message is received from Kanata (heartbeat for connection state)
    static let kanataTcpHeartbeat = Notification.Name("KeyPath.KanataTcpHeartbeat")
    /// Posted when a physical key is pressed/released (userInfo["key"] = String, ["action"] = "press"/"release")
    static let kanataKeyInput = Notification.Name("KeyPath.KanataKeyInput")
    /// Posted when a tap-hold key transitions to hold state (userInfo["key"] = String, ["action"] = String)
    static let kanataHoldActivated = Notification.Name("KeyPath.KanataHoldActivated")
    /// Posted when a tap-hold key triggers its tap action (userInfo["key"] = String, ["action"] = String)
    static let kanataTapActivated = Notification.Name("KeyPath.KanataTapActivated")
    /// Posted when a one-shot modifier is activated (userInfo["key"] = String, ["modifiers"] = String)
    static let kanataOneShotActivated = Notification.Name("KeyPath.KanataOneShotActivated")
    /// Posted when a chord resolves (userInfo["keys"] = String, ["action"] = String)
    static let kanataChordResolved = Notification.Name("KeyPath.KanataChordResolved")
    /// Posted when a tap-dance resolves (userInfo["key"] = String, ["tapCount"] = Int, ["action"] = String)
    static let kanataTapDanceResolved = Notification.Name("KeyPath.KanataTapDanceResolved")
    /// Posted when a generic push-msg is received (userInfo["message"] = String) - e.g., "icon:arrow-left", "emphasis:h,j,k,l"
    static let kanataMessagePush = Notification.Name("KeyPath.KanataMessagePush")
}
