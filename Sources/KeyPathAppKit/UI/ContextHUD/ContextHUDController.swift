import AppKit
import KeyPathCore
import SwiftUI

/// Singleton controller for the Context HUD floating window.
/// Listens for layer changes and shows a compact, auto-dismissing HUD
/// with available key mappings for the current context.
@MainActor
final class ContextHUDController {
    static let shared = ContextHUDController()

    var window: ContextHUDWindow?
    var hostingView: NSHostingView<ContextHUDView>?
    let viewModel = ContextHUDViewModel()
    let layerKeyMapper = LayerKeyMapper.shared
    let kindaVimStateAdapter = KindaVimStateAdapter.shared
    var hasStartedKindaVimStateMonitoring = false

    var kindaVimPackInstalled = false

    var dismissTask: Task<Void, Never>?
    var layerMapTask: Task<Void, Never>?
    private var previousLayer: String = "base"

    var holdLabelCache: [String: [UInt16: String]] = [:]
    var cachedEnabledCollections: [RuleCollection]?

    private let oneShotOverride = OneShotLayerOverrideState(
        timeoutDuration: .seconds(5)
    )

    static let modifierKeys: Set<String> = [
        "leftshift", "rightshift", "leftalt", "rightalt",
        "leftctrl", "rightctrl", "leftmeta", "rightmeta",
        "capslock", "fn"
    ]

    var precomputeTask: Task<Void, Never>?

    // MARK: - Backtick cheat-sheet trigger

    var backtickMonitor: Any?
    var cheatSheetDismissKeyMonitor: Any?
    var cheatSheetDismissClickMonitor: Any?
    var cheatSheetVisible = false

    private init() {
        setupNotificationObservers()
        Task { @MainActor in await self.refreshKindaVimPackInstalled() }
        startBacktickMonitor()
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
            forName: .installedPacksChanged,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.refreshKindaVimPackInstalled()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .kanataLayerChanged,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
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
            queue: NotificationObserverManager.mainOperationQueue
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
            queue: NotificationObserverManager.mainOperationQueue
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
            queue: NotificationObserverManager.mainOperationQueue
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
            queue: NotificationObserverManager.mainOperationQueue
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
            queue: NotificationObserverManager.mainOperationQueue
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
        let triggerMode = PreferencesService.shared.contextHUDTriggerMode
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
                // One-shot override is only needed in tap-to-toggle mode.
                // In hold-to-show mode, push layer events should not block the
                // subsequent Kanata "base" event on release.
                if triggerMode == .tapToToggle {
                    if normalized == "base" {
                        oneShotOverride.clear()
                    } else {
                        oneShotOverride.activate(normalized)
                    }
                } else if normalized == "base" {
                    oneShotOverride.clear()
                }
            case "kanata":
                if normalized == "base" {
                    // Always honor Kanata's return-to-base signal.
                    // Ignoring this causes the HUD to get stuck on nav.
                    oneShotOverride.clear()
                } else if triggerMode == .tapToToggle,
                          oneShotOverride.shouldIgnoreKanataUpdate(normalizedLayer: normalized)
                {
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
        if Self.isEscapeKeyName(key) {
            // Ensure overlay/layer indicators return to base even if Kanata layer-exit
            // push messages are missed or delayed.
            _ = ActionDispatcher.shared.dispatch(message: "layer:base")
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
        if hasStartedKindaVimStateMonitoring {
            kindaVimStateAdapter.stopMonitoring()
            hasStartedKindaVimStateMonitoring = false
        }
        window?.orderOut(nil)
        window = nil
        hostingView = nil
        viewModel.clear()
    }

    // MARK: - Collection Cache

    func loadEnabledCollections() async -> [RuleCollection] {
        if let cached = cachedEnabledCollections {
            return cached
        }
        let all = await RuleCollectionStore.shared.loadCollections()
        let enabled = all.filter(\.isEnabled)
        cachedEnabledCollections = enabled
        return enabled
    }

    private static func isEscapeKeyName(_ key: String) -> Bool {
        if let keyCode = KeyboardVisualizationViewModel.kanataNameToKeyCode(key) {
            return keyCode == 53
        }
        let normalized = key.lowercased()
        return normalized == "esc" || normalized == "escape"
    }

    // MARK: - Background Precompute

    static let precomputeLayers = ["nav", "launcher"]

    // showForLayer, resolveHoldLabels, precomputeNavLayer → ContextHUDController+ShowForLayer.swift
    // showWindow, dismiss, scheduleDismiss, createWindow, positionWindow → ContextHUDController+Window.swift
    // buildLauncherKeyMap, preloadLauncherIcons → ContextHUDController+Window.swift
    // startBacktickMonitor, handleBacktickCandidate, showKindaVimCheatSheet → ContextHUDController+Window.swift
    // installCheatSheetDismissMonitors, dismissCheatSheet → ContextHUDController+Window.swift

    private func refreshKindaVimPackInstalled() async {
        let installed = await InstalledPackTracker.shared
            .isInstalled(packID: PackRegistry.kindaVim.id)
        await MainActor.run { self.kindaVimPackInstalled = installed }
    }
}
