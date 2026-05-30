import Foundation
import KeyPathCore

extension LiveKeyboardOverlayController {
    // MARK: - Key Click Handling

    func handleKeymapChanged(keymapId: String, includePunctuation: Bool) {
        guard let ruleCollectionsManager else {
            AppLogger.shared.log("⚠️ [OverlayController] Cannot apply keymap - RuleCollectionsManager not configured")
            return
        }

        AppLogger.shared.log("⌨️ [OverlayController] Keymap changed to '\(keymapId)' (punctuation: \(includePunctuation))")

        Task { @MainActor in
            let conflicts = await ruleCollectionsManager.setActiveKeymap(keymapId, includePunctuation: includePunctuation)

            if !conflicts.isEmpty {
                AppLogger.shared.log("⚠️ [OverlayController] Keymap change had \(conflicts.count) conflict(s)")
            }
        }
    }

    func handleKeyClick(key: PhysicalKey, layerInfo: LayerKeyInfo?) {
        if key.layoutRole == .touchId {
            toggleInspectorPanel()
            return
        }

        guard kanataViewModel != nil else {
            AppLogger.shared.log("⚠️ [OverlayController] Cannot open Mapper - KanataViewModel not configured")
            return
        }

        let inputKey = OverlayKeyboardView.keyCodeToKanataName(key.keyCode)

        if viewModel.isLauncherModeActive {
            let normalizedKey = inputKey.lowercased()

            if normalizedKey == "esc" {
                AppLogger.shared.log("🖱️ [OverlayController] Launcher cancel clicked (esc)")
                ActionDispatcher.shared.dispatch(message: "layer:base")
                return
            }

            // When inspector or Pack Detail window is open, clicking a launcher key opens the editor
            let inspectorOpen = uiState.isInspectorOpen || uiState.inspectorReveal > 0
            let packDetailOpen = PackDetailWindowController.shared.currentPackID == PackRegistry.launcher.id
            if inspectorOpen || packDetailOpen {
                AppLogger.shared.log("🖱️ [OverlayController] Launcher key clicked for editing: \(normalizedKey)")
                NotificationCenter.default.post(
                    name: .launcherSelectKey,
                    object: nil,
                    userInfo: ["key": normalizedKey]
                )
                return
            }

            if let mapping = viewModel.launcherMappings[normalizedKey],
               let message = Self.launcherActionMessage(for: mapping.action)
            {
                AppLogger.shared.log("🖱️ [OverlayController] Launcher key clicked: \(normalizedKey) -> \(message)")
                ActionDispatcher.shared.dispatch(message: message)
                ActionDispatcher.shared.dispatch(message: "layer:base")
                return
            }
        }

        let outputKey: String = if let simpleOutput = layerInfo?.outputKey {
            simpleOutput
        } else if let displayLabel = layerInfo?.displayLabel, !displayLabel.isEmpty {
            displayLabel
        } else {
            inputKey
        }

        let currentLayer = viewModel.currentLayerName

        AppLogger.shared.log("🖱️ [OverlayController] Key clicked: \(key.label) (keyCode: \(key.keyCode)) -> \(outputKey) [layer: \(currentLayer)]")

        let inspectorVisible = uiState.isInspectorOpen || uiState.isInspectorAnimating || uiState.inspectorReveal > 0
        guard inspectorVisible else {
            AppLogger.shared.log("🖱️ [OverlayController] Key click ignored (drawer not visible)")
            return
        }

        viewModel.selectedKeyCode = key.keyCode

        var userInfo: [String: Any] = [
            "keyCode": key.keyCode,
            "inputKey": inputKey,
            "outputKey": outputKey,
            "layer": currentLayer,
        ]
        if let displayLabel = layerInfo?.displayLabel, !displayLabel.isEmpty {
            userInfo["displayLabel"] = displayLabel
        }
        if let appId = layerInfo?.appLaunchIdentifier {
            userInfo["appIdentifier"] = appId
        }
        if let systemId = layerInfo?.systemActionIdentifier {
            userInfo["systemActionIdentifier"] = systemId
        }
        if let urlId = layerInfo?.urlIdentifier {
            userInfo["urlIdentifier"] = urlId
        }
        if let shiftedOutput = kanataViewModel?.underlyingManager.getCustomRule(forInput: inputKey)?.shiftedOutput {
            userInfo["shiftedOutputKey"] = shiftedOutput
        }
        Foundation.NotificationCenter.default.post(
            name: Foundation.Notification.Name.mapperDrawerKeySelected,
            object: nil,
            userInfo: userInfo
        )
    }

    func handleKeyDoubleClick(key: PhysicalKey, layerInfo _: LayerKeyInfo?) {
        guard viewModel.isLauncherModeActive else { return }
        let inputKey = OverlayKeyboardView.keyCodeToKanataName(key.keyCode)
        let normalizedKey = inputKey.lowercased()

        AppLogger.shared.log("🖱️ [OverlayController] Launcher key double-clicked for editing: \(normalizedKey)")

        let inspectorOpen = uiState.isInspectorOpen || uiState.inspectorReveal > 0
        if !inspectorOpen {
            toggleInspectorPanel()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .launcherSelectKey,
                object: nil,
                userInfo: ["key": normalizedKey]
            )
        }
    }
}
