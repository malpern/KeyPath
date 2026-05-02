import Foundation
import KeyPathCore

extension LiveKeyboardOverlayController {
    // MARK: - Layer State

    enum LayerChangeSource: String {
        case push
        case kanata
        case unknown
    }

    func updateLayerName(_ layerName: String) {
        viewModel.updateLayer(layerName)
    }

    var currentLayerName: String {
        viewModel.currentLayerName
    }

    func lookupCurrentMapping(forKeyCode keyCode: UInt16) -> (layer: String, info: LayerKeyInfo)? {
        guard let info = viewModel.layerKeyMap[keyCode] else {
            return nil
        }
        return (layer: viewModel.currentLayerName, info: info)
    }

    func setLoadingLayerMap(_ isLoading: Bool) {
        viewModel.isLoadingLayerMap = isLoading
    }

    func setupLayerChangeObserver() {
        Foundation.NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.kanataLayerChanged,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak self] (notification: Foundation.Notification) in
            guard let layerName = notification.userInfo?["layerName"] as? String else { return }
            let sourceRaw = notification.userInfo?["source"] as? String
            Task { @MainActor in
                guard let self else { return }
                let source = LayerChangeSource(rawValue: sourceRaw ?? "") ?? .unknown
                self.handleLayerChange(layerName, source: source)
            }
        }

        Foundation.NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.kanataConfigChanged,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak self] (_: Foundation.Notification) in
            AppLogger.shared.info("🔔 [OverlayController] Received kanataConfigChanged notification - invalidating layer mappings")
            Task { @MainActor in
                self?.viewModel.invalidateLayerMappings()
            }
        }
    }

    func setupKeyInputObserver() {
        Foundation.NotificationCenter.default.addObserver(
            forName: Foundation.Notification.Name.kanataKeyInput,
            object: nil,
            queue: NotificationObserverManager.mainOperationQueue
        ) { [weak self] (notification: Foundation.Notification) in
            let key = notification.userInfo?["key"] as? String
            let action = notification.userInfo?["action"] as? String
            Task { @MainActor in
                guard let self else { return }
                guard let key, action == "press" else { return }

                if let overrideLayer = self.oneShotOverride.clearOnKeyPress(
                    key,
                    modifierKeys: Self.modifierKeys
                ) {
                    AppLogger.shared.debug(
                        "🧭 [OverlayController] Clearing one-shot layer override '\(overrideLayer)' on key press: \(key)"
                    )
                }

                // Allow physical Escape to always dismiss momentary/one-shot layer state.
                // This recovers from missed layer-exit notifications.
                if Self.isEscapeKeyName(key), self.currentLayerName.lowercased() != "base" {
                    _ = ActionDispatcher.shared.dispatch(message: "layer:base")
                }
            }
        }
    }

    func handleLayerChange(_ layerName: String, source: LayerChangeSource) {
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

    static let modifierKeys: Set<String> = [
        "leftshift",
        "rightshift",
        "leftalt",
        "rightalt",
        "leftctrl",
        "rightctrl",
        "leftmeta",
        "rightmeta",
        "capslock",
        "fn",
    ]

    static func isEscapeKeyName(_ key: String) -> Bool {
        if let keyCode = KeyboardVisualizationViewModel.kanataNameToKeyCode(key) {
            return keyCode == 53
        }
        let normalized = key.lowercased()
        return normalized == "esc" || normalized == "escape"
    }
}
