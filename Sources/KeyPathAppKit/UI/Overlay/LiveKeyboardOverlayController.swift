import AppKit
import SwiftUI
import Combine

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
    private var isUserResizing = false
    private var inspectorAnimationToken = UUID()
    private var resizeAnchor: ResizeAnchor = .none
    private var resizeStartMouse: NSPoint = .zero
    private var resizeStartFrame: NSRect = .zero
    private var cancellables = Set<AnyCancellable>()

    /// Timestamp when overlay was auto-hidden for settings (for restore on close)
    private var autoHiddenTimestamp: Date?

    /// Duration within which we'll restore the overlay when settings closes (10 minutes)
    private let restoreWindowDuration: TimeInterval = 10 * 60

    /// Reference to KanataViewModel for opening Mapper window
    private weak var kanataViewModel: KanataViewModel?

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
    private let inspectorAnimationDuration: TimeInterval = 2.35
    private var inspectorTotalWidth: CGFloat {
        inspectorPanelWidth + OverlayLayoutMetrics.inspectorSeamWidth
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
    func configure(kanataViewModel: KanataViewModel) {
        self.kanataViewModel = kanataViewModel
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

    func toggleInspectorPanel() {
        if uiState.isInspectorOpen || uiState.inspectorReveal > 0 {
            closeInspector(animated: true)
        } else {
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
        if uiState.desiredContentHeight > 0 {
            applyDesiredContentHeight(uiState.desiredContentHeight)
        }
        window?.orderFront(nil)
    }

    private func hideWindow() {
        viewModel.stopCapturing()
        closeInspector(animated: false)
        window?.orderOut(nil)
    }

    // MARK: - Key Click Handling

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
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.setFrameSize(initialSize)

        // Borderless, resizable window
        let window = OverlayWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isMovableByWindowBackground = false // Disabled - using custom resize/move handling
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.delegate = self

        // Always on top but not activating - prevents window from becoming key/main
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        // Prevent the window from ever becoming key window (so it doesn't steal keyboard focus)
        // Note: This relies on OverlayWindow.canBecomeKey returning false

        // Allow resize - constrain to keyboard aspect ratio
        // Min: 150pt height -> keyboard area = 96pt -> width = 96 * 2.53 + 28 = 271
        // Max: 500pt height -> keyboard area = 446pt -> width = 446 * 2.53 + 28 = 1156
        window.minSize = NSSize(width: 270, height: 150)
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

        uiState.isInspectorAnimating = shouldAnimate
        uiState.inspectorReveal = 0

        if shouldAnimate {
            let windowExpansionDuration: TimeInterval = 0.25
            setWindowFrame(expandedFrame, animated: true, duration: windowExpansionDuration)
            DispatchQueue.main.asyncAfter(deadline: .now() + windowExpansionDuration) { [weak self] in
                guard let self, self.inspectorAnimationToken == token else { return }
                withAnimation(.easeInOut(duration: self.inspectorAnimationDuration)) {
                    self.uiState.inspectorReveal = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + self.inspectorAnimationDuration) { [weak self] in
                    guard let self, self.inspectorAnimationToken == token else { return }
                    self.uiState.isInspectorOpen = true
                    self.uiState.isInspectorAnimating = false
                    self.lastWindowFrame = expandedFrame
                }
            }
        } else {
            setWindowFrame(expandedFrame, animated: false)
            uiState.inspectorReveal = 1
            uiState.isInspectorOpen = true
            uiState.isInspectorAnimating = false
            lastWindowFrame = expandedFrame
        }
    }

    private func closeInspector(animated: Bool) {
        guard let window else { return }
        let targetFrame = collapsedFrameBeforeInspector ?? InspectorPanelLayout.collapsedFrame(
            expandedFrame: window.frame,
            inspectorWidth: inspectorTotalWidth
        )
        let token = UUID()
        inspectorAnimationToken = token
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        uiState.isInspectorAnimating = shouldAnimate

        if shouldAnimate {
            withAnimation(.easeInOut(duration: inspectorAnimationDuration)) {
                uiState.inspectorReveal = 0
            }
            setWindowFrame(targetFrame, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + inspectorAnimationDuration) { [weak self] in
                guard let self, self.inspectorAnimationToken == token else { return }
                self.uiState.isInspectorOpen = false
                self.uiState.isInspectorAnimating = false
                self.collapsedFrameBeforeInspector = nil
                self.lastWindowFrame = targetFrame
            }
        } else {
            setWindowFrame(targetFrame, animated: false)
            uiState.inspectorReveal = 0
            uiState.isInspectorOpen = false
            uiState.isInspectorAnimating = false
            collapsedFrameBeforeInspector = nil
            lastWindowFrame = targetFrame
        }
    }

    private func handleWindowFrameChange() {
        guard let window else { return }
        if uiState.isInspectorOpen {
            updateCollapsedFrame(forExpandedFrame: window.frame)
        }
        if uiState.isInspectorAnimating {
            return
        }
        saveWindowFrame()
        lastWindowFrame = window.frame
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
                self.applyDesiredContentHeight(height)
            }
            .store(in: &cancellables)
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
    @Published var desiredContentHeight: CGFloat = 0
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
