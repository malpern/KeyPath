import AppKit
import KeyPathCore
import SwiftUI

/// Singleton controller for the Context HUD floating window.
/// Listens for layer changes and shows a compact, auto-dismissing HUD
/// with available key mappings for the current context.
@MainActor
final class ContextHUDController {
    static let shared = ContextHUDController()

    private var window: ContextHUDWindow?
    private var hostingView: NSHostingView<ContextHUDView>?
    private let viewModel = ContextHUDViewModel()
    private let layerKeyMapper = LayerKeyMapper()

    private var dismissTask: Task<Void, Never>?
    private var layerMapTask: Task<Void, Never>?
    private var previousLayer: String = "base"

    private let oneShotOverride = OneShotLayerOverrideState(
        timeoutNanoseconds: 5_000_000_000
    )

    private static let modifierKeys: Set<String> = [
        "leftshift", "rightshift", "leftalt", "rightalt",
        "leftctrl", "rightctrl", "leftmeta", "rightmeta",
        "capslock", "fn",
    ]

    private init() {
        setupNotificationObservers()
        AppLogger.shared.log("🎯 [ContextHUD] Controller initialized")
    }

    /// Test-only initializer that skips notification observers
    init(testMode: Bool) {
        if !testMode {
            setupNotificationObservers()
        }
        AppLogger.shared.log("🎯 [ContextHUD] Controller initialized (testMode: \(testMode))")
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .kanataLayerChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let layerName = notification.userInfo?["layerName"] as? String else { return }
            let sourceRaw = notification.userInfo?["source"] as? String
            Task { @MainActor in
                guard let self else { return }
                self.handleLayerChange(layerName, source: sourceRaw)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .kanataKeyInput,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let key = notification.userInfo?["key"] as? String
            let action = notification.userInfo?["action"] as? String
            Task { @MainActor in
                guard let self else { return }
                self.handleKeyInput(key: key, action: action)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .kanataConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                AppLogger.shared.info("🎯 [ContextHUD] Config changed - invalidating cache")
                await self.layerKeyMapper.invalidateCache()
            }
        }
    }

    // MARK: - Layer Change Handling

    func handleLayerChange(_ layerName: String, source: String?) {
        let normalized = layerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Check display mode preference
        let displayMode = PreferencesService.shared.contextHUDDisplayMode
        guard displayMode == .hudOnly || displayMode == .both else {
            return
        }

        // Handle one-shot override to avoid flicker
        if let source {
            switch source {
            case "push":
                if normalized == "base" {
                    oneShotOverride.clear()
                } else {
                    oneShotOverride.activate(normalized)
                }
            case "kanata":
                if normalized == "base" {
                    // If one-shot override is active, ignore Kanata's "base" report.
                    // The override will be cleared by key press or timeout instead.
                    if oneShotOverride.currentLayer != nil {
                        return
                    }
                } else if oneShotOverride.shouldIgnoreKanataUpdate(normalizedLayer: normalized) {
                    return
                }
            default:
                break
            }
        }

        // Skip if no actual layer change
        guard normalized != previousLayer.lowercased() else { return }
        previousLayer = layerName

        // Base layer → dismiss (layer deactivated via hold release or one-shot consumption)
        if normalized == "base" {
            dismiss()
            return
        }

        // Non-base layer → show HUD with key data
        showForLayer(layerName)
    }

    func handleKeyInput(key: String?, action: String?) {
        guard let key, action == "press" else { return }

        // Clear one-shot override on non-modifier key press
        if let overrideLayer = oneShotOverride.clearOnKeyPress(key, modifierKeys: Self.modifierKeys) {
            AppLogger.shared.debug("🎯 [ContextHUD] Clearing one-shot override '\(overrideLayer)' on key press: \(key)")
        }

        // Dismiss on Escape (manual override for both modes)
        if key.lowercased() == "esc" {
            dismiss()
        }
    }

    /// Whether the HUD window is currently visible (internal for testing)
    var isVisible: Bool {
        window?.isVisible ?? false
    }

    /// The current previous layer (internal for testing)
    var currentPreviousLayer: String {
        previousLayer
    }

    /// Reset state for testing
    func resetForTesting() {
        previousLayer = "base"
        dismissTask?.cancel()
        dismissTask = nil
        layerMapTask?.cancel()
        layerMapTask = nil
        window?.orderOut(nil)
        window = nil
        hostingView = nil
        viewModel.clear()
    }

    // MARK: - Show / Dismiss

    private func showForLayer(_ layerName: String) {
        // Cancel any pending dismiss
        dismissTask?.cancel()
        dismissTask = nil

        // Cancel any in-flight mapping task
        layerMapTask?.cancel()

        layerMapTask = Task { [weak self] in
            guard let self else { return }

            do {
                let configPath = WizardSystemPaths.userConfigPath
                let allCollections = await RuleCollectionStore.shared.loadCollections()
                let enabledCollections = allCollections.filter(\.isEnabled)

                // Get the active layout
                let layoutId = UserDefaults.standard.string(forKey: LayoutPreferences.layoutIdKey) ?? LayoutPreferences.defaultLayoutId
                let layout = PhysicalLayout.find(id: layoutId) ?? .macBookUS

                // Build key mapping for this layer
                let keyMap = try await layerKeyMapper.getMapping(
                    for: layerName,
                    configPath: configPath,
                    layout: layout,
                    collections: enabledCollections
                )

                guard !Task.isCancelled else { return }

                // Resolve content style
                let style = HUDContentResolver.resolve(
                    layerName: layerName,
                    keyMap: keyMap,
                    collections: enabledCollections
                )

                // Update view model
                viewModel.update(
                    layerName: layerName,
                    keyMap: keyMap,
                    collections: enabledCollections,
                    style: style
                )

                // Show the window — dismissal is driven by layer→base change,
                // matching how the overlay behaves (no auto-dismiss timer).
                showWindow()
            } catch {
                AppLogger.shared.error("🎯 [ContextHUD] Failed to build layer mapping: \(error)")
            }
        }
    }

    private func showWindow() {
        if window == nil {
            createWindow()
        }

        guard let window else { return }

        // Update the hosting view content
        if let hostingView {
            hostingView.rootView = ContextHUDView(viewModel: viewModel)
        }

        // Position at center of screen
        positionWindow()

        // Animate in: scale + fade
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let bounds = contentView.bounds
            contentView.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)

            contentView.layer?.transform = CATransform3DMakeScale(0.95, 0.95, 1.0)
            contentView.alphaValue = 0

            window.orderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentView.animator().alphaValue = 1.0
                contentView.layer?.transform = CATransform3DIdentity
            }
        } else {
            window.orderFront(nil)
        }

        AppLogger.shared.debug("🎯 [ContextHUD] Showing HUD for layer '\(viewModel.layerName)'")
    }

    private func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil

        guard let window, window.isVisible else { return }

        // Animate out: scale + fade
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let bounds = contentView.bounds
            contentView.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                contentView.animator().alphaValue = 0
                contentView.layer?.transform = CATransform3DMakeScale(0.95, 0.95, 1.0)
            } completionHandler: {
                Task { @MainActor in
                    window.orderOut(nil)
                    // Reset for next show
                    contentView.alphaValue = 1.0
                    contentView.layer?.transform = CATransform3DIdentity
                }
            }
        } else {
            window.orderOut(nil)
        }

        AppLogger.shared.debug("🎯 [ContextHUD] Dismissed")
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        let timeout = PreferencesService.shared.contextHUDTimeout
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    // MARK: - Window Creation & Positioning

    private func createWindow() {
        let hudView = ContextHUDView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: hudView)
        hosting.setFrameSize(NSSize(width: 400, height: 240))

        let newWindow = ContextHUDWindow(contentView: hosting)
        hostingView = hosting
        window = newWindow
    }

    private func positionWindow() {
        guard let window, let screen = NSScreen.main else { return }

        // Size to fit content
        if let hostingView {
            let fittingSize = hostingView.fittingSize
            let width = min(max(fittingSize.width, 240), 800)
            let height = min(max(fittingSize.height, 100), 600)
            window.setContentSize(NSSize(width: width, height: height))
        }

        // Position at center of screen
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        let x = screenFrame.midX - (windowFrame.width / 2)
        let y = screenFrame.midY - (windowFrame.height / 2)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
