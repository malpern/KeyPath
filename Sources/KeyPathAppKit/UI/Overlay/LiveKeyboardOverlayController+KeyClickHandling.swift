import Foundation
import KeyPathCore
import KeyPathRulesCore

extension LiveKeyboardOverlayController {
    // MARK: - Key Click Handling

    func handleKeymapChanged(keymapId: String, includePunctuation: Bool) {
        guard let ruleCollectionsManager else {
            AppLogger.shared.log("⚠️ [OverlayController] Cannot apply keymap - RuleCollectionsManager not configured")
            return
        }

        AppLogger.shared.log("⌨️ [OverlayController] Keymap changed to '\(keymapId)' (punctuation: \(includePunctuation))")

        Task { @MainActor in
            // AppStorage observes rollback too. Do not turn restoration of the
            // already-active selection into another save/reload attempt.
            guard ruleCollectionsManager.activeKeymapId != keymapId
                || ruleCollectionsManager.keymapIncludesPunctuation != includePunctuation
            else { return }
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

        let userInfo = mapperSelection(key: key, layerInfo: layerInfo)
        AppLogger.shared.log("🖱️ [OverlayController] Key clicked: \(key.label) (keyCode: \(key.keyCode)) -> \(userInfo["outputKey"] ?? inputKey) [layer: \(viewModel.currentLayerName)]")

        guard isInspectorVisible else {
            AppLogger.shared.log("🖱️ [OverlayController] Key click ignored (drawer not visible)")
            return
        }

        viewModel.selectedKeyCode = key.keyCode
        Foundation.NotificationCenter.default.post(
            name: Foundation.Notification.Name.mapperDrawerKeySelected,
            object: nil,
            userInfo: userInfo
        )
    }

    var isInspectorVisible: Bool {
        uiState.isInspectorOpen || uiState.isInspectorAnimating || uiState.inspectorReveal > 0
    }

    /// Right-click "Remap…": show this key in the mapper, opening the drawer if needed.
    /// A drawer that is not on screen yet receives the key as a pending selection,
    /// because the mapper selects its default key when it appears.
    func openMapper(for key: PhysicalKey, layerInfo: LayerKeyInfo?) {
        guard key.layoutRole != .touchId, kanataViewModel != nil else { return }
        let userInfo = mapperSelection(key: key, layerInfo: layerInfo)
        AppLogger.shared.log("🖱️ [OverlayController] Remap requested from context menu: \(key.label) (keyCode: \(key.keyCode))")
        viewModel.selectedKeyCode = key.keyCode
        MapperDrawerSelectionRequest.pending = userInfo
        UserDefaults.standard.set(InspectorSection.mapper.rawValue, forKey: "inspectorSection")
        if isInspectorVisible {
            Foundation.NotificationCenter.default.post(
                name: Foundation.Notification.Name.mapperDrawerKeySelected,
                object: nil,
                userInfo: userInfo
            )
        } else {
            toggleInspectorPanel()
        }
    }

    /// Right-click "Reset to Default": remove the user's own rule for this key on
    /// the current layer through the canonical rule transaction.
    func resetKeyToDefault(_ key: PhysicalKey) {
        guard let kanataViewModel else { return }
        let input = OverlayKeyboardView.keyCodeToKanataName(key.keyCode)
        guard let rule = Self.resettableRule(input: input, layer: viewModel.currentLayerName,
                                             in: kanataViewModel.customRules) else { return }
        AppLogger.shared.log("🖱️ [OverlayController] Reset to default from context menu: \(input) [layer: \(viewModel.currentLayerName)]")
        Task { await kanataViewModel.removeCustomRule(rule.id) }
    }

    /// Only rules the user made, for this input, on this layer. Pack rules and
    /// other layers are excluded: Reset removes exactly what the key shows here.
    static func resettableRule(input: String, layer: String, in rules: [CustomRule]) -> CustomRule? {
        rules.first {
            $0.packSource == nil && $0.input.caseInsensitiveCompare(input) == .orderedSame
                && $0.targetLayer.kanataName == layer.lowercased()
        }
    }

    static func resettableInputs(in rules: [CustomRule], layer: String) -> Set<String> {
        Set(rules.filter { $0.packSource == nil && $0.targetLayer.kanataName == layer.lowercased() }
            .map { $0.input.lowercased() })
    }

    func mapperSelection(key: PhysicalKey, layerInfo: LayerKeyInfo?) -> [String: Any] {
        let inputKey = OverlayKeyboardView.keyCodeToKanataName(key.keyCode)
        let outputKey: String = if let simpleOutput = layerInfo?.outputKey {
            simpleOutput
        } else if let displayLabel = layerInfo?.displayLabel, !displayLabel.isEmpty {
            displayLabel
        } else {
            inputKey
        }
        let currentLayer = viewModel.currentLayerName

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
        return userInfo
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

/// One-shot key selection for a mapper that is not on screen yet. Consumed when
/// the mapper appears, or cleared when a visible mapper handles the selection.
@MainActor
enum MapperDrawerSelectionRequest {
    static var pending: [String: Any]?

    static func take() -> [String: Any]? {
        defer { pending = nil }
        return pending
    }
}
