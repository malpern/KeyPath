import Foundation
import KeyPathCore
import KeyPathPermissions
import KeyPathRulesCore

extension RuleCollectionsManager {
    // MARK: - Event Monitoring

    /// Start listening for engine events (layer changes, action URIs, key input)
    /// over the running worker's control socket.
    func startEventMonitoring() {
        AppLogger.shared.log("🌐 [RuleCollectionsManager] Starting event monitoring")
        guard !TestEnvironment.isRunningTests else {
            AppLogger.shared.log("🌐 [RuleCollectionsManager] Skipping event monitoring (test environment)")
            return
        }

        eventMonitoringTask?.cancel()
        eventMonitoringTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await eventListener.start(
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
                onKeyInput: { observation in
                    // Feed investigation tracker for duplicate key analysis
                    let transition = await DuplicateKeyInvestigationTracker.shared.record(observation)
                    if DuplicateInvestigationSupport.isEnabled() {
                        AppLogger.shared.info(DuplicateInvestigationSupport.makeKeyTransitionLog(transition))
                    }

                    await MainActor.run {
                        NotificationCenter.default.post(observation)
                    }
                },
                onHoldActivated: { activation in
                    await MainActor.run {
                        NotificationCenter.default.post(activation)
                    }
                },
                onTapActivated: { activation in
                    await MainActor.run {
                        NotificationCenter.default.post(activation)
                    }
                },
                onOneShotActivated: { activation in
                    await MainActor.run {
                        NotificationCenter.default.post(activation)
                    }
                },
                onChordResolved: { resolution in
                    await MainActor.run {
                        NotificationCenter.default.post(resolution)
                    }
                },
                onTapDanceResolved: { resolution in
                    await MainActor.run {
                        NotificationCenter.default.post(resolution)
                    }
                },
                onHrmTrace: { trace in
                    await MainActor.run {
                        NotificationCenter.default.post(trace)
                    }
                },
                onCapabilitiesUpdated: { capabilities in
                    await MainActor.run {
                        NotificationCenter.default.post(KanataCapabilitiesUpdate(capabilities: capabilities))
                    }
                },
                onGrabStatus: { active, reason in
                    await MainActor.run {
                        NotificationCenter.default.post(KanataGrabStatus(active: active, reason: reason))
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

        // Post to keystroke history (skip layer: URIs — already shown as layer dividers)
        if actionURI.action != "layer" {
            NotificationCenter.default.post(KanataActionDispatched(uri: actionURI))
        }

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

        // Forward icon and emphasis messages to keyboard visualization.
        NotificationCenter.default.post(KanataMessagePush(message: message))

        // Also notify external observers
        onUnknownMessage?(message)
    }

    func extractOpenURLPayload(from message: String) -> String? {
        guard message.lowercased().hasPrefix("open:") else { return nil }
        let payloadStart = message.index(message.startIndex, offsetBy: 5)
        let payload = String(message[payloadStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return payload.isEmpty ? nil : payload
    }

    /// Stop the event monitoring task and its underlying listener
    func stopEventMonitoring() async {
        eventMonitoringTask?.cancel()
        eventMonitoringTask = nil
        await eventListener.stop()
        AppLogger.shared.log("🌐 [RuleCollectionsManager] Stopped event monitoring")
    }
}
