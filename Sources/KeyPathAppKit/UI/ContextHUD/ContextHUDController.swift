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

    /// Cached hold labels per layer name (avoids Phase 2 jump on repeat activations)
    private var holdLabelCache: [String: [UInt16: String]] = [:]

    /// Cached enabled collections (avoids ~200ms disk I/O per layer activation)
    private var cachedEnabledCollections: [RuleCollection]?

    private let oneShotOverride = OneShotLayerOverrideState(
        timeoutDuration: .seconds(5)
    )

    private static let modifierKeys: Set<String> = [
        "leftshift", "rightshift", "leftalt", "rightalt",
        "leftctrl", "rightctrl", "leftmeta", "rightmeta",
        "capslock", "fn"
    ]

    /// Background precompute task (cancelled on config change)
    private var precomputeTask: Task<Void, Never>?

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

        // Also handle "layer:" push-msg messages (e.g., from fakekey layer broadcasts)
        // These arrive via .kanataMessagePush when layer-while-held doesn't generate
        // a LayerChange TCP event. Mirrors KeyboardVisualizationViewModel+TCP handling.
        NotificationCenter.default.addObserver(
            forName: .kanataMessagePush,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let message = notification.userInfo?["message"] as? String,
                  message.hasPrefix("layer:")
            else { return }
            let layerName = String(message.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            Task { @MainActor in
                guard let self else { return }
                self.handleLayerChange(layerName, source: "push")
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
            forName: .kanataHoldActivated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let key = notification.userInfo?["key"] as? String
            let action = notification.userInfo?["action"] as? String
            Task { @MainActor in
                guard let self else { return }
                self.handleHoldActivated(key: key, action: action)
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
                self.holdLabelCache.removeAll()
                self.cachedEnabledCollections = nil
                await self.layerKeyMapper.invalidateCache()
                // Re-precompute after debounce to avoid thrashing
                self.precomputeNavLayer(debounce: true)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .ruleCollectionsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cachedEnabledCollections = nil
            }
        }
    }

    // MARK: - Layer Change Handling

    func handleLayerChange(_ layerName: String, source: String?) {
        let normalized = layerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        AppLogger.shared.debug("🎯 [ContextHUD] handleLayerChange: '\(layerName)' normalized='\(normalized)' source=\(source ?? "nil") prev='\(previousLayer)'")

        // Context HUD list is an experimental feature - skip when disabled
        guard FeatureFlags.contextHUDListEnabled else { return }

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
            // Kick off background precompute on first base event (Kanata is ready)
            if precomputeTask == nil {
                precomputeNavLayer()
            }
            dismiss()
            return
        }

        // Non-base layer → show HUD with key data
        showForLayer(layerName)
    }

    func handleKeyInput(key: String?, action: String?) {
        guard let key else { return }

        if let keyCode = KeyboardVisualizationViewModel.kanataNameToKeyCode(key) {
            if action == "press" {
                viewModel.pressedKeyCodes.insert(keyCode)
            } else if action == "release" {
                viewModel.pressedKeyCodes.remove(keyCode)
                viewModel.activeHoldLabels.removeValue(forKey: keyCode)
            }
        }

        guard action == "press" else { return }

        // Clear one-shot override on non-modifier key press
        if let overrideLayer = oneShotOverride.clearOnKeyPress(key, modifierKeys: Self.modifierKeys) {
            AppLogger.shared.debug("🎯 [ContextHUD] Clearing one-shot override '\(overrideLayer)' on key press: \(key)")
        }

        // Dismiss on Escape (manual override for both modes)
        if key.lowercased() == "esc" {
            dismiss()
        }
    }

    func handleHoldActivated(key: String?, action: String?) {
        guard let key, let action else { return }
        guard let keyCode = KeyboardVisualizationViewModel.kanataNameToKeyCode(key) else { return }
        let displayLabel = KeyboardVisualizationViewModel.actionToDisplayLabel(action)
        viewModel.activeHoldLabels[keyCode] = displayLabel
    }

    /// Whether the HUD window is currently visible (internal for testing)
    var isVisible: Bool {
        window?.isVisible ?? false
    }

    /// The current previous layer (internal for testing)
    var currentPreviousLayer: String {
        previousLayer
    }

    /// The view model (internal for testing)
    var testViewModel: ContextHUDViewModel {
        viewModel
    }

    /// Reset state for testing
    func resetForTesting() {
        previousLayer = "base"
        holdLabelCache.removeAll()
        cachedEnabledCollections = nil
        precomputeTask?.cancel()
        precomputeTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        layerMapTask?.cancel()
        layerMapTask = nil
        window?.orderOut(nil)
        window = nil
        hostingView = nil
        viewModel.clear()
    }

    // MARK: - Collection Cache

    /// Load enabled collections, using in-memory cache when available
    private func loadEnabledCollections() async -> [RuleCollection] {
        if let cached = cachedEnabledCollections {
            return cached
        }
        let all = await RuleCollectionStore.shared.loadCollections()
        let enabled = all.filter(\.isEnabled)
        cachedEnabledCollections = enabled
        return enabled
    }

    // MARK: - Background Precompute

    /// Layers to precompute in the background (most commonly activated)
    private static let precomputeLayers = ["nav", "launcher"]

    /// Warm the LayerKeyMapper cache and hold labels for common layers
    /// so the first activation is instant. Runs entirely off the main thread.
    /// - Parameter debounce: Whether to debounce (use on config change, skip on startup)
    private func precomputeNavLayer(debounce: Bool = false) {
        precomputeTask?.cancel()
        precomputeTask = Task { [weak self] in
            guard let self else { return }
            if debounce {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
            }

            AppLogger.shared.info("🎯 [ContextHUD] Background precompute starting")

            let configPath = WizardSystemPaths.userConfigPath
            let enabledCollections = await self.loadEnabledCollections()
            let layoutId = UserDefaults.standard.string(forKey: LayoutPreferences.layoutIdKey) ?? LayoutPreferences.defaultLayoutId
            let layout = PhysicalLayout.find(id: layoutId) ?? .macBookUS

            for layerName in Self.precomputeLayers {
                guard !Task.isCancelled else { return }

                do {
                    if layerName == "launcher" {
                        let keyMap = self.buildLauncherKeyMap(from: enabledCollections)
                        await self.preloadLauncherIcons(keyMap: keyMap)
                        AppLogger.shared.info("🎯 [ContextHUD] Precomputed launcher icons")
                    } else {
                        // Warm the simulator cache
                        let keyMap = try await self.layerKeyMapper.getMapping(
                            for: layerName,
                            configPath: configPath,
                            layout: layout,
                            collections: enabledCollections
                        )
                        guard !Task.isCancelled else { return }

                        // Warm the hold label cache
                        if FeatureFlags.simulatorAndVirtualKeysEnabled {
                            let holdLabels = await self.resolveHoldLabels(
                                keyMap: keyMap,
                                configPath: configPath,
                                layerName: layerName
                            )
                            guard !Task.isCancelled else { return }
                            if !holdLabels.isEmpty {
                                self.holdLabelCache[layerName] = holdLabels
                            }
                        }
                        AppLogger.shared.info("🎯 [ContextHUD] Precomputed layer '\(layerName)'")
                    }
                } catch {
                    AppLogger.shared.debug("🎯 [ContextHUD] Precompute failed for '\(layerName)': \(error)")
                }
            }

            AppLogger.shared.info("🎯 [ContextHUD] Background precompute complete")
        }
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
                let enabledCollections = await self.loadEnabledCollections()

                // Get the active layout
                let layoutId = UserDefaults.standard.string(forKey: LayoutPreferences.layoutIdKey) ?? LayoutPreferences.defaultLayoutId
                let layout = PhysicalLayout.find(id: layoutId) ?? .macBookUS

                let normalizedLayerName = layerName.lowercased()

                // Build launcher keyMap from collections (not simulator).
                // The kanata simulator cannot capture push-msg events, so launcher
                // keys appear transparent when simulated. Build from config directly.
                let collectionLauncherKeyMap = buildLauncherKeyMap(from: enabledCollections)

                let keyMap: [UInt16: LayerKeyInfo]
                let launcherKeyMap: [UInt16: LayerKeyInfo]? = nil

                if normalizedLayerName == "launcher" {
                    // Launcher layer: use collection-built keyMap as primary
                    keyMap = collectionLauncherKeyMap

                    // Preload all app icons and favicons before showing,
                    // so the layout doesn't jitter as icons load async
                    await preloadLauncherIcons(keyMap: keyMap)
                } else {
                    // Other layers: use simulator for primary keyMap
                    keyMap = try await layerKeyMapper.getMapping(
                        for: layerName,
                        configPath: configPath,
                        layout: layout,
                        collections: enabledCollections
                    )
                }

                guard !Task.isCancelled else { return }

                // Resolve content style based on the layer's own content
                let style = HUDContentResolver.resolve(
                    layerName: layerName,
                    keyMap: keyMap,
                    collections: enabledCollections
                )

                guard !Task.isCancelled else { return }

                // Resolve hold labels: use cache or fetch before showing
                var holdLabels = self.holdLabelCache[normalizedLayerName] ?? [:]

                if holdLabels.isEmpty, FeatureFlags.simulatorAndVirtualKeysEnabled {
                    holdLabels = await resolveHoldLabels(
                        keyMap: keyMap,
                        configPath: configPath,
                        layerName: layerName
                    )
                    guard !Task.isCancelled else { return }
                    if !holdLabels.isEmpty {
                        self.holdLabelCache[normalizedLayerName] = holdLabels
                    }
                }

                guard !Task.isCancelled else { return }

                // Show HUD with complete data (tap + hold labels)
                viewModel.update(
                    layerName: layerName,
                    keyMap: keyMap,
                    collections: enabledCollections,
                    style: style,
                    holdLabels: holdLabels,
                    launcherKeyMap: launcherKeyMap
                )

                showWindow()
            } catch {
                AppLogger.shared.error("🎯 [ContextHUD] Failed to build layer mapping: \(error)")
            }
        }
    }

    /// Resolve hold labels for tap-hold keys via simulator
    private func resolveHoldLabels(
        keyMap: [UInt16: LayerKeyInfo],
        configPath: String,
        layerName: String
    ) async -> [UInt16: String] {
        // Filter to non-transparent, non-layer-switch keys
        let candidates = keyMap.filter { _, info in
            !info.isTransparent && !info.isLayerSwitch
        }
        guard !candidates.isEmpty else { return [:] }

        var result: [UInt16: String] = [:]
        await withTaskGroup(of: (UInt16, String?).self) { group in
            for (keyCode, info) in candidates {
                group.addTask { [layerKeyMapper] in
                    do {
                        let label = try await layerKeyMapper.holdDisplayLabel(
                            for: keyCode,
                            configPath: configPath,
                            startLayer: layerName
                        )
                        // Filter out hold == tap (not a real tap-hold)
                        if let label, label != info.displayLabel {
                            return (keyCode, label)
                        }
                        return (keyCode, nil)
                    } catch {
                        return (keyCode, nil)
                    }
                }
            }
            for await (keyCode, label) in group {
                if let label {
                    result[keyCode] = label
                }
            }
        }
        return result
    }

    private func showWindow() {
        if window == nil {
            createWindow()
        }

        guard let window else { return }

        // Update the hosting view content and force initial layout pass
        if let hostingView {
            hostingView.rootView = ContextHUDView(viewModel: viewModel)
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
        }

        // Hide content immediately — prevents flash of stale layout
        window.contentView?.alphaValue = 0

        // Defer to next runloop iteration so SwiftUI fully settles its layout.
        // Without this, fittingSize can be stale on first view causing a visible jump.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }

            // Second layout pass after SwiftUI has settled
            if let hostingView = self.hostingView {
                hostingView.invalidateIntrinsicContentSize()
                hostingView.layoutSubtreeIfNeeded()
            }

            // Size and position with accurate fittingSize
            self.positionWindow()

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

            AppLogger.shared.debug("🎯 [ContextHUD] Showing HUD for layer '\(self.viewModel.layerName)'")
        }
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
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    // MARK: - Launcher KeyMap from Collections

    /// Build a launcher keyMap directly from LauncherGridConfig in rule collections.
    /// The kanata simulator cannot capture push-msg events, so launcher keys appear
    /// transparent when simulated. This bypasses the simulator entirely.
    private func buildLauncherKeyMap(from collections: [RuleCollection]) -> [UInt16: LayerKeyInfo] {
        guard let launcherCollection = collections.first(where: { $0.id == RuleCollectionIdentifier.launcher }),
              let config = launcherCollection.configuration.launcherGridConfig
        else {
            return [:]
        }

        var keyMap: [UInt16: LayerKeyInfo] = [:]
        let collectionId = launcherCollection.id

        for mapping in config.mappings where mapping.isEnabled {
            guard let keyCode = KeyboardVisualizationViewModel.kanataNameToKeyCode(mapping.key) else {
                continue
            }

            let info: LayerKeyInfo = switch mapping.target {
            case let .app(name, bundleId):
                .appLaunch(appIdentifier: bundleId ?? name, collectionId: collectionId)
            case let .url(urlString):
                .webURL(url: urlString, collectionId: collectionId)
            case .folder, .script:
                .pushMsg(message: mapping.target.displayName, collectionId: collectionId)
            }

            keyMap[keyCode] = info
        }

        return keyMap
    }

    /// Preload app icons and favicons so the launcher HUD doesn't jitter
    private func preloadLauncherIcons(keyMap: [UInt16: LayerKeyInfo]) async {
        await withTaskGroup(of: Void.self) { group in
            for (_, info) in keyMap {
                if let appId = info.appLaunchIdentifier {
                    // App icons are synchronous (already cached by IconResolverService)
                    _ = IconResolverService.shared.resolveAppIcon(for: appId)
                }
                if let url = info.urlIdentifier {
                    // Favicons are async — preload them
                    group.addTask {
                        _ = await IconResolverService.shared.resolveFavicon(for: url)
                    }
                }
            }
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
            // Force SwiftUI layout pass so fittingSize reflects current content,
            // not stale layout from a previous show/update cycle.
            hostingView.invalidateIntrinsicContentSize()
            hostingView.layoutSubtreeIfNeeded()

            let fittingSize = hostingView.fittingSize
            let width = min(max(fittingSize.width, 240), 1100)
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
