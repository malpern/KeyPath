import AppKit
import Combine
import SwiftUI

/// Controls the floating live keyboard overlay window.
/// Creates an always-on-top borderless window that shows the live keyboard state.
/// Uses CGEvent tap for reliable key detection (same as "See Keymap" feature).
import KeyPathCore

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
    private var resizeAnchor: ResizeAnchor = .none
    private var resizeStartMouse: NSPoint = .zero
    private var resizeStartFrame: NSRect = .zero
    private var inspectorDebugLastLog: CFTimeInterval = 0
    private var cancellables = Set<AnyCancellable>()

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
        static let windowX = "LiveKeyboardOverlay.windowX"
        static let windowY = "LiveKeyboardOverlay.windowY"
        static let windowWidth = "LiveKeyboardOverlay.windowWidth"
        static let windowHeight = "LiveKeyboardOverlay.windowHeight"
        /// Migration key to reset frame when aspect ratio changes
        static let frameVersion = "LiveKeyboardOverlay.frameVersion"
    }

    /// Current frame version - increment to reset saved frames after layout changes
    private let currentFrameVersion = 6
    private let inspectorPanelWidth: CGFloat = 240
    private let inspectorAnimationDuration: TimeInterval = 1.0
    private let baseKeyboardAspectRatio: CGFloat = PhysicalLayout.macBookUS.totalWidth / PhysicalLayout.macBookUS.totalHeight
    private let minKeyboardHeight: CGFloat = 180
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
        let keyboardWidth = minKeyboardHeight * baseKeyboardAspectRatio
        return keyboardWidth
            + OverlayLayoutMetrics.keyboardPadding
            + OverlayLayoutMetrics.keyboardTrailingPadding
            + OverlayLayoutMetrics.outerHorizontalPadding * 2
    }

    /// Shared instance for app-wide access
    static let shared = LiveKeyboardOverlayController()

    override private init() {
        super.init()
        setupLayerChangeObserver()
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
            if let layerName = notification.userInfo?["layerName"] as? String {
                Task { @MainActor in
                    self?.updateLayerName(layerName)
                }
            }
        }

        // Listen for config changes to rebuild layer mapping
        NotificationCenter.default.addObserver(
            forName: .kanataConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel.invalidateLayerMappings()
            }
        }
    }

    /// Restore overlay state from previous session
    func restoreState() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: DefaultsKey.isVisible) {
            isVisible = true
        }
    }

    /// Configure the KanataViewModel reference for opening Mapper from overlay clicks
    func configure(kanataViewModel: KanataViewModel, ruleCollectionsManager: RuleCollectionsManager? = nil) {
        self.kanataViewModel = kanataViewModel
        self.ruleCollectionsManager = ruleCollectionsManager
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
    func toggle() {
        isVisible = !isVisible
    }

    /// Reset the overlay window to its default size and position
    func resetWindowFrame() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKey.windowWidth)
        defaults.removeObject(forKey: DefaultsKey.windowHeight)
        defaults.removeObject(forKey: DefaultsKey.windowX)
        defaults.removeObject(forKey: DefaultsKey.windowY)

        // If window is currently visible, close and reopen to apply default frame
        if isVisible {
            hideWindow()
            showWindow()
        }

        AppLogger.shared.log("🔧 [OverlayController] Window frame reset to defaults")
    }

    func toggleInspectorPanel() {
        AppLogger.shared.log("🔧 [OverlayController] toggleInspectorPanel called - isInspectorOpen=\(uiState.isInspectorOpen), reveal=\(uiState.inspectorReveal)")
        if uiState.isInspectorOpen || uiState.inspectorReveal > 0 {
            AppLogger.shared.log("🔧 [OverlayController] Closing inspector...")
            closeInspector(animated: true)
        } else {
            if let window {
                let minInspectorHeight = OverlayLayoutMetrics.verticalChrome + minInspectorKeyboardHeight
                if window.frame.height < minInspectorHeight {
                    // Auto-resize window to minimum height required for inspector
                    AppLogger.shared.log("📐 [OverlayController] Auto-resizing window from \(window.frame.height.rounded())pt to \(minInspectorHeight)pt for inspector")
                    var newFrame = window.frame
                    let heightDelta = minInspectorHeight - newFrame.height
                    newFrame.size.height = minInspectorHeight
                    // Adjust width to maintain aspect ratio
                    let keyboardHeight = minInspectorHeight - OverlayLayoutMetrics.verticalChrome
                    let keyboardWidth = keyboardHeight * baseKeyboardAspectRatio
                    let horizontalChrome = OverlayLayoutMetrics.keyboardPadding
                        + OverlayLayoutMetrics.keyboardTrailingPadding
                        + OverlayLayoutMetrics.outerHorizontalPadding * 2
                    newFrame.size.width = keyboardWidth + horizontalChrome
                    // Keep bottom-left anchored (move origin down by height increase)
                    newFrame.origin.y -= heightDelta
                    window.setFrame(newFrame, display: true, animate: true)
                }
            }
            AppLogger.shared.log("🔧 [OverlayController] Opening inspector...")
            openInspector(animated: true)
        }
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
           !isVisible {
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

    /// Handle click on a key in the overlay - opens Mapper with preset values
    private func handleKeyClick(key: PhysicalKey, layerInfo: LayerKeyInfo?) {
        if key.layoutRole == .touchId {
            toggleInspectorPanel()
            return
        }

        guard let kanataViewModel else {
            AppLogger.shared.log("⚠️ [OverlayController] Cannot open Mapper - KanataViewModel not configured")
            return
        }

        // Convert key code to kanata name for input label
        let inputKey = OverlayKeyboardView.keyCodeToKanataName(key.keyCode)

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

        // Open Mapper with preset values, current layer, and input keyCode
        MapperWindowController.shared.showWindow(
            viewModel: kanataViewModel,
            presetInput: inputKey,
            presetOutput: outputKey,
            layer: currentLayer,
            inputKeyCode: key.keyCode,
            appIdentifier: layerInfo?.appLaunchIdentifier,
            systemActionIdentifier: layerInfo?.systemActionIdentifier,
            urlIdentifier: layerInfo?.urlIdentifier
        )
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
        let defaults = UserDefaults.standard
        defaults.set(frame.origin.x, forKey: DefaultsKey.windowX)
        defaults.set(frame.origin.y, forKey: DefaultsKey.windowY)
        defaults.set(frame.size.width, forKey: DefaultsKey.windowWidth)
        defaults.set(height, forKey: DefaultsKey.windowHeight)
    }

    private func restoreWindowFrame() -> NSRect? {
        let defaults = UserDefaults.standard

        // Check frame version - if outdated, clear saved frame to apply new defaults
        let savedVersion = defaults.integer(forKey: DefaultsKey.frameVersion)
        if savedVersion < currentFrameVersion {
            // Clear old frame data
            defaults.removeObject(forKey: DefaultsKey.windowWidth)
            defaults.removeObject(forKey: DefaultsKey.windowHeight)
            defaults.removeObject(forKey: DefaultsKey.windowX)
            defaults.removeObject(forKey: DefaultsKey.windowY)
            defaults.set(currentFrameVersion, forKey: DefaultsKey.frameVersion)
            return nil
        }

        // Check if we have saved values (width > 0 means we've saved before)
        let width = defaults.double(forKey: DefaultsKey.windowWidth)
        guard width > 0 else { return nil }

        let x = defaults.double(forKey: DefaultsKey.windowX)
        let y = defaults.double(forKey: DefaultsKey.windowY)
        let height = defaults.double(forKey: DefaultsKey.windowHeight)
        guard height > 0 else {
            defaults.removeObject(forKey: DefaultsKey.windowWidth)
            defaults.removeObject(forKey: DefaultsKey.windowHeight)
            defaults.removeObject(forKey: DefaultsKey.windowX)
            defaults.removeObject(forKey: DefaultsKey.windowY)
            return nil
        }
        return NSRect(x: x, y: y, width: width, height: height)
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

        func heightForWidth(_ width: CGFloat) -> CGFloat {
            let keyboardWidth = max(0, width - horizontalChrome)
            return verticalChrome + (keyboardWidth / aspect)
        }

        func widthForHeight(_ height: CGFloat) -> CGFloat {
            let keyboardHeight = max(0, height - verticalChrome)
            return horizontalChrome + (keyboardHeight * aspect)
        }

        let widthDelta = abs(frameSize.width - currentSize.width)
        let heightDelta = abs(frameSize.height - currentSize.height)

        var newWidth: CGFloat
        var newHeight: CGFloat

        let anchor = resolveResizeAnchor(
            widthDelta: widthDelta,
            heightDelta: heightDelta
        )

        if anchor == .height {
            newHeight = clamp(frameSize.height, min: minSize.height, max: maxSize.height)
            newWidth = widthForHeight(newHeight)
        } else {
            newWidth = clamp(frameSize.width, min: minSize.width, max: maxSize.width)
            newHeight = heightForWidth(newWidth)
        }

        if newWidth < minSize.width {
            newWidth = minSize.width
            newHeight = heightForWidth(newWidth)
        } else if newWidth > maxSize.width {
            newWidth = maxSize.width
            newHeight = heightForWidth(newWidth)
        }

        if newHeight < minSize.height {
            newHeight = minSize.height
            newWidth = widthForHeight(newHeight)
        } else if newHeight > maxSize.height {
            newHeight = maxSize.height
            newWidth = widthForHeight(newHeight)
        }

        return NSSize(width: newWidth, height: newHeight)
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

        let contentView = LiveKeyboardOverlayView(
            viewModel: viewModel,
            uiState: uiState,
            inspectorWidth: inspectorPanelWidth,
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
            }
        )

        // Pass kanataViewModel as environment object for OverlayLaunchersSection
        let wrappedContent = if let kanataVM = kanataViewModel {
            AnyView(contentView.environmentObject(kanataVM))
        } else {
            AnyView(contentView)
        }

        let hostingView = NSHostingView(rootView: wrappedContent)
        hostingView.setFrameSize(initialSize)

        // Borderless, resizable window
        // In accessibility test mode, use titled window for automation tools like Peekaboo
        let useAccessibilityTestMode = ProcessInfo.processInfo.environment["KEYPATH_ACCESSIBILITY_TEST_MODE"] != nil
        let windowStyle: NSWindow.StyleMask = useAccessibilityTestMode
            ? [.titled, .resizable, .closable] // Standard window for automation
            : [.borderless, .resizable] // Normal borderless overlay

        let window = OverlayWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: windowStyle,
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isMovableByWindowBackground = false // Disabled - using custom resize/move handling
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.delegate = self

        // Accessibility: Make window discoverable by automation tools (Peekaboo, etc.)
        window.title = "KeyPath Keyboard Overlay" // Title for window listing
        window.setAccessibilityIdentifier("keypath-keyboard-overlay-window")
        window.setAccessibilityLabel("KeyPath Keyboard Overlay")

        // Always on top but not activating - prevents window from becoming key/main
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
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
            let x = screenFrame.maxX - windowFrame.width - 20
            let y = screenFrame.minY + 20
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.window = window
        observeDesiredContentHeight()
        observeDesiredContentWidth()
        observeKeyboardAspectRatio()
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
            // Start timer to smoothly animate reveal (windowDidResize doesn't fire continuously)
            let startTime = CACurrentMediaTime()
            let startReveal = uiState.inspectorReveal
            inspectorAnimationTimer?.invalidate()
            inspectorAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                let elapsed = CACurrentMediaTime() - startTime
                let progress = min(1.0, elapsed / inspectorAnimationDuration)
                // Use ease-in-out curve to match NSAnimationContext
                let easedProgress = easeInOutProgress(progress)
                uiState.inspectorReveal = startReveal + (1 - startReveal) * easedProgress

                if progress >= 1.0 {
                    timer.invalidate()
                    inspectorAnimationTimer = nil
                }
            }

            setWindowFrame(expandedFrame, animated: true, duration: inspectorAnimationDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + inspectorAnimationDuration) { [weak self] in
                guard let self, inspectorAnimationToken == token else { return }
                inspectorAnimationTimer?.invalidate()
                inspectorAnimationTimer = nil
                uiState.isInspectorOpen = true
                uiState.isInspectorAnimating = false
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
            // Start timer to smoothly animate reveal (windowDidResize doesn't fire continuously)
            let startTime = CACurrentMediaTime()
            let startReveal = uiState.inspectorReveal
            inspectorAnimationTimer?.invalidate()
            inspectorAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                let elapsed = CACurrentMediaTime() - startTime
                let progress = min(1.0, elapsed / inspectorAnimationDuration)
                // Use ease-in-out curve to match NSAnimationContext
                let easedProgress = easeInOutProgress(progress)
                uiState.inspectorReveal = startReveal * (1 - easedProgress)

                if progress >= 1.0 {
                    timer.invalidate()
                    inspectorAnimationTimer = nil
                }
            }

            setWindowFrame(targetFrame, animated: true, duration: inspectorAnimationDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + inspectorAnimationDuration) { [weak self] in
                guard let self, inspectorAnimationToken == token else { return }
                inspectorAnimationTimer?.invalidate()
                inspectorAnimationTimer = nil
                uiState.inspectorReveal = 0
                uiState.isInspectorOpen = false
                uiState.isInspectorAnimating = false
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
        let reveal = (window.frame.width - collapsedWidth) / inspectorTotalWidth
        uiState.inspectorReveal = max(0, min(1, reveal))
    }

    /// Ease-in-out timing function to match NSAnimationContext's .easeInEaseOut
    /// Core Animation uses cubic bezier control points (0.42, 0, 0.58, 1.0)
    private func easeInOutProgress(_ t: CGFloat) -> CGFloat {
        // Attempt 7: Exact cubic bezier matching CAMediaTimingFunction.easeInEaseOut
        // Control points: P0=(0,0), P1=(0.42,0), P2=(0.58,1), P3=(1,1)
        evaluateCubicBezierY(t: t, p1y: 0.0, p2y: 1.0, p1x: 0.42, p2x: 0.58)
    }

    /// Evaluate cubic bezier curve Y value for a given X (time) value
    /// Uses Newton-Raphson iteration to find t parameter, then evaluates Y
    private func evaluateCubicBezierY(t inputX: CGFloat, p1y: CGFloat, p2y: CGFloat, p1x: CGFloat, p2x: CGFloat) -> CGFloat {
        // For simple ease-in-out where x and y curves are symmetric, we can use a simpler approach
        // The bezier curve: B(t) = 3(1-t)²t·P1 + 3(1-t)t²·P2 + t³
        // For easeInEaseOut (0.42, 0, 0.58, 1), we need to solve for t given x, then compute y

        // Newton-Raphson to find t for given x
        var tGuess = inputX
        for _ in 0 ..< 8 {
            let x = bezierValue(t: tGuess, p1: p1x, p2: p2x)
            let dx = bezierDerivative(t: tGuess, p1: p1x, p2: p2x)
            if abs(dx) < 0.00001 { break }
            tGuess -= (x - inputX) / dx
            tGuess = max(0, min(1, tGuess))
        }

        // Now compute Y at this t
        return bezierValue(t: tGuess, p1: p1y, p2: p2y)
    }

    /// Cubic bezier value: B(t) = 3(1-t)²t·p1 + 3(1-t)t²·p2 + t³
    private func bezierValue(t: CGFloat, p1: CGFloat, p2: CGFloat) -> CGFloat {
        let oneMinusT = 1 - t
        return 3 * oneMinusT * oneMinusT * t * p1 + 3 * oneMinusT * t * t * p2 + t * t * t
    }

    /// Derivative of cubic bezier: B'(t) = 3(1-t)²·p1 + 6(1-t)t·(p2-p1) + 3t²·(1-p2)
    private func bezierDerivative(t: CGFloat, p1: CGFloat, p2: CGFloat) -> CGFloat {
        let oneMinusT = 1 - t
        return 3 * oneMinusT * oneMinusT * p1 + 6 * oneMinusT * t * (p2 - p1) + 3 * t * t * (1 - p2)
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
                guard let self, let window, !self.isUserResizing else { return }
                resizeWindowForNewAspectRatio(newAspectRatio)
            }
            .store(in: &cancellables)
    }

    private func resizeWindowForNewAspectRatio(_ newAspectRatio: CGFloat) {
        guard let window else { return }
        guard !isAdjustingHeight, !isAdjustingWidth else { return }

        let verticalChrome = OverlayLayoutMetrics.verticalChrome
        let currentFrame = window.frame
        let currentKeyboardHeight = currentFrame.height - verticalChrome

        // Calculate new keyboard width based on new aspect ratio
        let newKeyboardWidth = currentKeyboardHeight * newAspectRatio

        // Calculate horizontal chrome (padding + inspector if open)
        let horizontalChrome = OverlayLayoutMetrics.horizontalChrome(
            inspectorVisible: uiState.isInspectorOpen,
            inspectorWidth: inspectorPanelWidth
        )

        let newWindowWidth = newKeyboardWidth + horizontalChrome

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

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(maxValue, Swift.max(minValue, value))
    }

    private func resolveResizeAnchor(widthDelta: CGFloat, heightDelta: CGFloat) -> ResizeAnchor {
        if resizeAnchor != .none {
            return resizeAnchor
        }

        let startSize = resizeStartFrame.size
        let hasStart = startSize != .zero
        let threshold: CGFloat = 6
        let currentMouse = NSEvent.mouseLocation
        let mouseDeltaX = abs(currentMouse.x - resizeStartMouse.x)
        let mouseDeltaY = abs(currentMouse.y - resizeStartMouse.y)

        if hasStart {
            let frameWidthDelta = abs(startSize.width - (window?.frame.size.width ?? startSize.width))
            let frameHeightDelta = abs(startSize.height - (window?.frame.size.height ?? startSize.height))
            if frameWidthDelta > threshold || frameHeightDelta > threshold {
                resizeAnchor = frameHeightDelta > frameWidthDelta ? .height : .width
                return resizeAnchor
            }
        }

        if mouseDeltaX > threshold || mouseDeltaY > threshold {
            resizeAnchor = mouseDeltaY > mouseDeltaX ? .height : .width
            return resizeAnchor
        }

        if heightDelta > widthDelta {
            resizeAnchor = .height
        } else {
            resizeAnchor = .width
        }
        return resizeAnchor
    }
}

private enum ResizeAnchor {
    case none
    case width
    case height
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

// MARK: - Notification Integration

extension Notification.Name {
    /// Posted when the live keyboard overlay should be toggled
    static let toggleLiveKeyboardOverlay = Notification.Name("KeyPath.ToggleLiveKeyboardOverlay")
    /// Posted when the Kanata layer changes (userInfo["layerName"] = String)
    static let kanataLayerChanged = Notification.Name("KeyPath.KanataLayerChanged")
    /// Posted when the Kanata config changes (rules saved, etc.)
    static let kanataConfigChanged = Notification.Name("KeyPath.KanataConfigChanged")
    /// Posted when a physical key is pressed/released (userInfo["key"] = String, ["action"] = "press"/"release")
    static let kanataKeyInput = Notification.Name("KeyPath.KanataKeyInput")
    /// Posted when a tap-hold key transitions to hold state (userInfo["key"] = String, ["action"] = String)
    static let kanataHoldActivated = Notification.Name("KeyPath.KanataHoldActivated")
    /// Posted when a generic push-msg is received (userInfo["message"] = String) - e.g., "icon:arrow-left", "emphasis:h,j,k,l"
    static let kanataMessagePush = Notification.Name("KeyPath.KanataMessagePush")
}
