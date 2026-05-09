import AppKit
import Foundation
import KeyPathCore
import KeyPathInstallationWizard
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
    var healthObserver: OverlayHealthIndicatorObserver?
    weak var hostingView: NSHostingView<LiveKeyboardOverlayView>?
    private let frameStore = OverlayWindowFrameStore()
    var hintWindowController: HideHintWindowController?
    var hintBubbleObserver: Task<Void, Never>?
    private var hiddenHintController: OverlayHiddenHintWindowController?

    weak var kanataViewModel: KanataViewModel?
    weak var ruleCollectionsManager: RuleCollectionsManager?

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

    /// Title bar height for the overlay window. Returns 0 for borderless, ~28 for titled.
    /// Used to convert between frame and content dimensions in sizing calculations.
    var windowTitleBarHeight: CGFloat {
        guard let window else { return 0 }
        return window.frame.height - window.contentRect(forFrameRect: window.frame).height
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

    let oneShotOverride = OneShotLayerOverrideState(
        timeoutDuration: LiveKeyboardOverlayController.oneShotTimeoutDuration
    )
    var isLauncherSessionActive = false
    var shouldRestoreAppHidden = false
    var shouldRestoreOverlayHidden = false
    var wasVisibleBeforeAppSuppression: Bool = false
    var isAppSuppressed: Bool = false

    override private init() {
        super.init()
        checkBuildVersionAndClearCacheIfNeeded()
        setupLayerChangeObserver()
        setupKeyInputObserver()
        setupOpenOverlayWithMapperObserver()
        setupAccessibilityTestModeObserver()
        setupWizardVisibilityObserver()
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

    var overlayHiddenByWizard = false

    private static let oneShotTimeoutDuration: Duration = .seconds(5)

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
        // because the observer guard prevents re-subscription.
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
        // startupSize is content-based; for titled windows, frame height must include title bar
        let frameHeight = startupSize.height + windowTitleBarHeight
        let x = screenFrame.midX - (startupSize.width / 2)
        let y = screenFrame.minY + bottomMargin

        let startupFrame = NSRect(x: x, y: y, width: startupSize.width, height: frameHeight)
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
                    Foundation.NotificationCenter.default.post(
                        name: Foundation.Notification.Name.showWizard,
                        object: nil
                    )
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
                // For titled windows, frame includes title bar — add it so comparison is frame-based
                let minInspectorFrameHeight = OverlayLayoutMetrics.verticalChrome + minInspectorKeyboardHeight + windowTitleBarHeight
                if window.frame.height < minInspectorFrameHeight {
                    // Auto-resize window to minimum height required for inspector
                    // Do this synchronously (no animation) to prevent keyboard movement before drawer opens
                    AppLogger.shared.log("📐 [OverlayController] Auto-resizing window from \(window.frame.height.rounded())pt to \(minInspectorFrameHeight)pt for inspector")
                    var newFrame = window.frame
                    newFrame.size.height = minInspectorFrameHeight
                    // Adjust width to maintain aspect ratio
                    let keyboardHeight = minInspectorKeyboardHeight
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
        var frame = OverlaySizingDefaults.resetCenteredFrame(
            visibleFrame: screen?.visibleFrame,
            aspectRatio: currentKeyboardAspectRatio,
            inspectorWidth: inspectorPanelWidth
        )
        // resetCenteredFrame returns content-based dimensions; for titled windows,
        // the frame height must include the title bar.
        let titleBar = windowTitleBarHeight
        if titleBar > 0 {
            frame.size.height += titleBar
            frame.origin.y -= titleBar / 2 // Keep vertically centered
        }
        return frame
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
        // For titled windows, the frame includes the title bar. Add it to verticalChrome
        // so the resizer correctly computes keyboard area from frame dimensions.
        let titleBarHeight = sender.frame.height - sender.contentRect(forFrameRect: sender.frame).height
        let verticalChrome = OverlayLayoutMetrics.verticalChrome + titleBarHeight
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

    func createWindow() {
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
        // Preference is authoritative; env var is only a fallback for when no explicit preference exists.
        let useAccessibilityTestMode = Self.resolveAccessibilityTestMode()
        AppLogger.shared.log("🪟 [OverlayController] createWindow: useAccessibilityTestMode=\(useAccessibilityTestMode)")
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
        // For titled windows, min/max are frame sizes and must include the title bar height.
        let titleBarHeight = window.frame.height - window.contentRect(forFrameRect: window.frame).height
        window.minSize = NSSize(width: minWindowWidth, height: minWindowHeight + titleBarHeight)
        window.maxSize = NSSize(width: 1160 + inspectorTotalWidth, height: 500 + titleBarHeight)

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

    private func buildRootView() -> LiveKeyboardOverlayView {
        LiveKeyboardOverlayView(
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
                self?.showOverlayHiddenHint()
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
    }

    private func refreshOverlayContent() {
        guard let hostingView else { return }
        hostingView.rootView = buildRootView()
    }

    // MARK: - Overlay Hidden Hint

    /// Show the "Overlay Hidden — press ⌥⌘K to bring it back" education message.
    /// Only shows up to 4 times total across app restarts.
    private func showOverlayHiddenHint() {
        let prefs = PreferencesService.shared
        guard prefs.overlayHiddenHintShowCount < 4 else { return }

        prefs.overlayHiddenHintShowCount += 1

        let controller = OverlayHiddenHintWindowController()
        hiddenHintController = controller
        controller.show()
    }
}
