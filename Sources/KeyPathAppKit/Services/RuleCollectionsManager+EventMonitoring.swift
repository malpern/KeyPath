import Foundation
import KeyPathCore
import KeyPathPermissions

extension RuleCollectionsManager {
    // MARK: - Event Monitoring

    /// Start listening for events from Kanata TCP server (layer changes, action URIs, key input)
    func startEventMonitoring(port: Int) {
        AppLogger.shared.log("🌐 [RuleCollectionsManager] Starting event monitoring on port \(port)")
        guard !TestEnvironment.isRunningTests else {
            AppLogger.shared.log("🌐 [RuleCollectionsManager] Skipping event monitoring (test environment)")
            return
        }

        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await eventListener.start(
                port: port,
                onLayerChange: { [weak self] layer in
                    guard let self else { return }
                    await MainActor.run {
                        self.updateActiveLayerName(layer)
                    }
                },
                onActionURI: { [weak self] actionURI in
                    guard let self else { return }
                    await MainActor.run {
                        self.handleActionURI(actionURI)
                    }
                },
                onUnknownMessage: { [weak self] message in
                    guard let self else { return }
                    await MainActor.run {
                        self.handleUnknownMessage(message)
                    }
                },
                onKeyInput: { key, action in
                    // Post notification for TCP-based physical key input events
                    // Used by KeyboardVisualizationViewModel for overlay highlighting
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataKeyInput,
                            object: nil,
                            userInfo: ["key": key, "action": action.rawValue.lowercased()]
                        )
                    }
                },
                onHoldActivated: { activation in
                    // Post notification when tap-hold key transitions to hold state
                    // Used by KeyboardVisualizationViewModel for showing hold labels
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataHoldActivated,
                            object: nil,
                            userInfo: ["key": activation.key, "action": activation.action]
                        )
                    }
                },
                onTapActivated: { activation in
                    // Post notification when tap-hold key triggers its tap action
                    // Used by KeyboardVisualizationViewModel for suppressing output keys
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataTapActivated,
                            object: nil,
                            userInfo: ["key": activation.key, "action": activation.action]
                        )
                    }
                },
                onOneShotActivated: { activation in
                    // Post notification when one-shot modifier key is activated
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataOneShotActivated,
                            object: nil,
                            userInfo: ["key": activation.key, "modifiers": activation.modifiers]
                        )
                    }
                },
                onChordResolved: { resolution in
                    // Post notification when chord (multi-key combo) resolves
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataChordResolved,
                            object: nil,
                            userInfo: ["keys": resolution.keys, "action": resolution.action]
                        )
                    }
                },
                onTapDanceResolved: { resolution in
                    // Post notification when tap-dance resolves to action
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .kanataTapDanceResolved,
                            object: nil,
                            userInfo: [
                                "key": resolution.key,
                                "tapCount": resolution.tapCount,
                                "action": resolution.action
                            ]
                        )
                    }
                }
            )
        }
    }

    /// Handle a keypath:// action URI received via push-msg
    func handleActionURI(_ actionURI: KeyPathActionURI) {
        AppLogger.shared.log("🎯 [RuleCollectionsManager] Action URI: \(actionURI.url.absoluteString)")

        // Dispatch to ActionDispatcher
        ActionDispatcher.shared.dispatch(actionURI)

        // Also notify any external observers
        onActionURI?(actionURI)
    }

    /// Handle an unknown (non-keypath://) message
    /// These are typically icon/emphasis messages: "icon:arrow-left", "emphasis:h,j,k,l"
    func handleUnknownMessage(_ message: String) {
        AppLogger.shared.log("📨 [RuleCollectionsManager] Push message: \(message)")

        if let urlPayload = extractOpenURLPayload(from: message) {
            let decoded = URLMappingFormatter.decodeFromPushMessage(urlPayload)
            let encoded = URLMappingFormatter.encodeForPushMessage(decoded)
            if let actionURI = KeyPathActionURI(string: "open:\(encoded)") {
                _ = ActionDispatcher.shared.dispatch(actionURI)
            }
        }

        // Post notification for keyboard visualization (icon/emphasis handling)
        NotificationCenter.default.post(
            name: .kanataMessagePush,
            object: nil,
            userInfo: ["message": message]
        )

        // Also notify external observers
        onUnknownMessage?(message)
    }

    func extractOpenURLPayload(from message: String) -> String? {
        guard message.lowercased().hasPrefix("open:") else { return nil }
        let payloadStart = message.index(message.startIndex, offsetBy: 5)
        let payload = String(message[payloadStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return payload.isEmpty ? nil : payload
    }

    /// Deprecated: Use startEventMonitoring instead
    @available(*, deprecated, renamed: "startEventMonitoring")
    func startLayerMonitoring(port: Int) {
        startEventMonitoring(port: port)
    }
}
