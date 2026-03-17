import Combine
import Foundation
import KeyPathCore
import SwiftUI

/// Orchestrates the auto-detect keyboard flow:
/// 1. Observes `HIDDeviceMonitor` for new connections
/// 2. Checks `DeviceLayoutBindingStore` for existing accepted binding → auto-switch
/// 3. No binding → runs `DeviceRecognitionService.recognize()` → shows toast
/// 4. No match → does nothing (user can still search manually)
@MainActor
@Observable
final class AutoDetectKeyboardController {
    static let shared = AutoDetectKeyboardController()

    // MARK: - Toast State

    var showingToast = false
    var toastKeyboardName = ""
    var toastIsAutoSwitch = false
    var pendingResult: DeviceRecognitionService.RecognitionResult?

    // MARK: - Private

    private var connectCancellable: AnyCancellable?
    private var disconnectCancellable: AnyCancellable?
    private var autoDismissTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    /// Tracks VID:PIDs of currently connected keyboards to avoid re-prompting.
    /// Cleared on disconnect so reconnecting the same keyboard triggers auto-switch.
    private var connectedVIDPIDs: Set<String> = []

    func startObserving() {
        // Use notifications (fire-once) instead of @Published (replays current value).
        // This prevents stale lastConnectedKeyboard from triggering on re-subscribe.
        connectCancellable = NotificationCenter.default
            .publisher(for: .hidKeyboardConnected)
            .compactMap { $0.userInfo?["event"] as? HIDDeviceMonitor.HIDKeyboardEvent }
            .sink { [weak self] event in
                Task { @MainActor in
                    await self?.handleNewKeyboard(event)
                }
            }

        disconnectCancellable = NotificationCenter.default
            .publisher(for: .hidKeyboardDisconnected)
            .compactMap { $0.userInfo?["event"] as? HIDDeviceMonitor.HIDKeyboardEvent }
            .sink { [weak self] event in
                Task { @MainActor in
                    self?.handleKeyboardDisconnected(event)
                }
            }
    }

    func stopObserving() {
        connectCancellable?.cancel()
        connectCancellable = nil
        disconnectCancellable?.cancel()
        disconnectCancellable = nil
    }

    // MARK: - Core Flow

    private func handleNewKeyboard(_ event: HIDDeviceMonitor.HIDKeyboardEvent) async {
        let vidPidKey = event.vidPidKey

        // Deduplicate while connected (don't re-prompt for already-connected device)
        guard !connectedVIDPIDs.contains(vidPidKey) else { return }
        connectedVIDPIDs.insert(vidPidKey)

        // Check for existing accepted binding → auto-switch silently
        if let binding = await DeviceLayoutBindingStore.shared.binding(
            vendorID: event.vendorID,
            productID: event.productID
        ) {
            AppLogger.shared.log("🔌 [AutoDetect] Known keyboard \(binding.keyboardName) — auto-switching to \(binding.layoutId)")
            UserDefaults.standard.set(binding.layoutId, forKey: LayoutPreferences.layoutIdKey)
            showAutoSwitchToast(keyboardName: binding.keyboardName)
            return
        }

        // No binding → try to recognize
        guard let result = await DeviceRecognitionService.shared.recognize(event: event) else {
            AppLogger.shared.log("🔌 [AutoDetect] No keyboard match for \(event.productName) (\(vidPidKey))")
            return
        }

        AppLogger.shared.log(
            "🔌 [AutoDetect] Recognized \(result.keyboardName) (built-in: \(result.isBuiltIn), path: \(result.qmkPath ?? "none"), source: \(result.source.rawValue), match: \(result.matchType.rawValue))"
        )

        // Show confirmation toast
        pendingResult = result
        toastKeyboardName = result.keyboardName
        toastIsAutoSwitch = false
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            showingToast = true
        }
        scheduleAutoDismiss(seconds: 8)
    }

    private func handleKeyboardDisconnected(_ event: HIDDeviceMonitor.HIDKeyboardEvent) {
        connectedVIDPIDs.remove(event.vidPidKey)
    }

    // MARK: - User Actions

    func acceptDetection() {
        guard let result = pendingResult else { return }
        autoDismissTask?.cancel()

        if result.isBuiltIn, let layoutId = result.layoutId {
            // Built-in layout: select directly
            UserDefaults.standard.set(layoutId, forKey: LayoutPreferences.layoutIdKey)
            saveBinding(result: result, layoutId: layoutId)
            AppLogger.shared.log("🔌 [AutoDetect] Accepted built-in layout: \(layoutId)")
        } else {
            // QMK import needed — run inline
            performQMKImport(result: result)
        }

        dismissToast()
    }

    func dismissToast() {
        autoDismissTask?.cancel()
        importTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            showingToast = false
        }
        pendingResult = nil
    }

    // MARK: - Helpers

    private func showAutoSwitchToast(keyboardName: String) {
        toastKeyboardName = keyboardName
        toastIsAutoSwitch = true
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            showingToast = true
        }
        scheduleAutoDismiss(seconds: 3)
    }

    private func scheduleAutoDismiss(seconds: TimeInterval) {
        autoDismissTask?.cancel()
        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }

    private func saveBinding(result: DeviceRecognitionService.RecognitionResult, layoutId: String) {
        let event = result.deviceEvent
        let binding = DeviceLayoutBindingStore.Binding(
            vendorProductKey: event.vidPidKey,
            layoutId: layoutId,
            keyboardName: result.keyboardName,
            acceptedAt: Date()
        )
        Task {
            do {
                try await DeviceLayoutBindingStore.shared.saveBinding(binding)
            } catch {
                AppLogger.shared.warn("🔌 [AutoDetect] Failed to save binding for \(result.keyboardName): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - QMK Import

    private func performQMKImport(result: DeviceRecognitionService.RecognitionResult) {
        guard let qmkPath = result.qmkPath else {
            AppLogger.shared.warn("🔌 [AutoDetect] Missing QMK path for '\(result.keyboardName)'")
            return
        }

        importTask = Task {
            do {
                let jsonData = try await QMKKeyboardDatabase.shared.fetchKeyboardData(byPath: qmkPath)
                guard !Task.isCancelled else { return }

                let info = try JSONDecoder().decode(QMKLayoutParser.QMKKeyboardInfo.self, from: jsonData)

                guard !info.layouts.isEmpty else {
                    AppLogger.shared.warn("🔌 [AutoDetect] No layout definitions found for '\(result.keyboardName)'")
                    return
                }

                let layoutId = "custom-\(UUID().uuidString)"

                // Try keymap-based parsing first, fall back to row-based
                let parseResult: QMKLayoutParser.ParseResult
                var cachedKeymapTokens: [String]?

                if let keymapTokens = await QMKKeyboardDatabase.shared.fetchDefaultKeymap(keyboardPath: qmkPath),
                   let keymapResult = QMKLayoutParser.parseWithKeymap(
                       data: jsonData,
                       keymapTokens: keymapTokens,
                       idOverride: layoutId,
                       nameOverride: result.keyboardName
                   )
                {
                    parseResult = keymapResult
                    cachedKeymapTokens = keymapTokens
                } else if let positionResult = QMKLayoutParser.parseByPositionWithQuality(
                    data: jsonData,
                    idOverride: layoutId,
                    nameOverride: result.keyboardName
                ) {
                    parseResult = positionResult
                } else {
                    AppLogger.shared.warn("🔌 [AutoDetect] Failed to parse layout for '\(result.keyboardName)'")
                    return
                }

                guard !Task.isCancelled else { return }

                let layoutName = "\(result.keyboardName)\(result.manufacturer.map { " by \($0)" } ?? "")"
                let sourceURL = "https://keyboards.qmk.fm/v1/keyboards/\(qmkPath)/info.json"

                await QMKImportService.shared.replaceQMKImport(
                    layout: parseResult.layout,
                    name: layoutName,
                    sourceURL: sourceURL,
                    layoutJSON: jsonData,
                    layoutVariant: nil,
                    defaultKeymap: cachedKeymapTokens,
                    keyboardPath: qmkPath
                )

                guard !Task.isCancelled else { return }

                // Switch to the imported layout and save the binding
                UserDefaults.standard.set(parseResult.layout.id, forKey: LayoutPreferences.layoutIdKey)
                saveBinding(result: result, layoutId: parseResult.layout.id)
                AppLogger.shared.log("🔌 [AutoDetect] Imported and selected QMK layout: \(layoutName)")

            } catch is CancellationError {
                AppLogger.shared.log("🔌 [AutoDetect] QMK import cancelled for '\(result.keyboardName)'")
            } catch {
                AppLogger.shared.warn("🔌 [AutoDetect] QMK import failed for '\(result.keyboardName)': \(error.localizedDescription)")
            }
        }
    }
}
