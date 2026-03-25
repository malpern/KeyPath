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

    private struct BaselineDisplayContext: Equatable {
        let layoutId: String
        let keymapId: String
        let includePunctuationStore: String
    }

    struct ConnectedKeyboard: Identifiable, Equatable {
        enum Status: Equatable {
            case remembered
            case suggested
            case possibleMatch
            case importRequired
            case unrecognized
        }

        let event: HIDDeviceMonitor.HIDKeyboardEvent
        var keyboardName: String
        var detectedKeyboardName: String?
        var manufacturer: String?
        var layoutId: String?
        var qmkPath: String?
        var source: KeyboardDetectionIndex.Source?
        var matchType: KeyboardDetectionIndex.MatchType?
        var confidence: KeyboardDetectionIndex.Confidence?
        var status: Status

        var id: String { event.id }
        var vidPidKey: String { event.vidPidKey }
        var canActivateOverlay: Bool {
            layoutId != nil && status != .possibleMatch
        }

        var subtitle: String {
            switch status {
            case .remembered:
                return layoutId.flatMap { PhysicalLayout.find(id: $0)?.name } ?? "Remembered keyboard"
            case .suggested:
                if let layoutId {
                    return PhysicalLayout.find(id: layoutId)?.name ?? "Suggested layout"
                }
                return "Suggested keyboard"
            case .possibleMatch:
                return detectedKeyboardName.map { "Possible match: \($0)" } ?? "Possible match"
            case .importRequired:
                return "Import required"
            case .unrecognized:
                return "Search for a layout"
            }
        }
    }

    enum ToastMode: Equatable {
        case autoSwitch
        case rememberKeyboard
        case importKeyboard
        case importingKeyboard
        case importSucceeded
        case importFailed
    }

    // MARK: - Toast State

    var showingToast = false
    var toastKeyboardName = ""
    var toastMode: ToastMode = .autoSwitch
    var toastConfidence: KeyboardDetectionIndex.Confidence = .high
    var toastErrorMessage: String?
    var pendingResult: DeviceRecognitionService.RecognitionResult?
    var connectedKeyboards: [ConnectedKeyboard] = []
    var activeKeyboardID: String?
    var isKeyboardSearchPresented = false
    var keyboardSearchQuery = ""

    // MARK: - Private

    private var connectCancellable: AnyCancellable?
    private var disconnectCancellable: AnyCancellable?
    private var autoDismissTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    /// Tracks VID:PIDs of currently connected keyboards to avoid re-prompting.
    /// Cleared on disconnect so reconnecting the same keyboard triggers auto-switch.
    private var connectedVIDPIDs: Set<String> = []
    private var recognitionResultsByKeyboardID: [String: DeviceRecognitionService.RecognitionResult] = [:]
    private var baselineDisplayContext: BaselineDisplayContext
    private let bindingStore: DeviceLayoutBindingStore
    private let displayContextStore: KeyboardDisplayContextStore
    private let recognitionService: DeviceRecognitionService
    private let initialKeyboardEventsProvider: () -> [HIDDeviceMonitor.HIDKeyboardEvent]

    private static let baselineLayoutDefaultsKey = "AutoDetectKeyboardController.baselineLayoutId"
    private static let baselineKeymapDefaultsKey = "AutoDetectKeyboardController.baselineKeymapId"
    private static let baselinePunctuationDefaultsKey = "AutoDetectKeyboardController.baselineIncludePunctuationStore"

    init(
        bindingStore: DeviceLayoutBindingStore = .shared,
        displayContextStore: KeyboardDisplayContextStore = .shared,
        recognitionService: DeviceRecognitionService = .shared,
        initialKeyboardEventsProvider: @escaping () -> [HIDDeviceMonitor.HIDKeyboardEvent] = {
            let current = HIDDeviceMonitor.shared.connectedKeyboards
            return current.isEmpty ? HIDDeviceMonitor.currentKeyboardSnapshot() : current
        }
    ) {
        let defaults = UserDefaults.standard
        self.baselineDisplayContext = BaselineDisplayContext(
            layoutId: defaults.string(forKey: Self.baselineLayoutDefaultsKey)
                ?? defaults.string(forKey: LayoutPreferences.layoutIdKey)
                ?? LayoutPreferences.defaultLayoutId,
            keymapId: defaults.string(forKey: Self.baselineKeymapDefaultsKey)
                ?? defaults.string(forKey: KeymapPreferences.keymapIdKey)
                ?? LogicalKeymap.defaultId,
            includePunctuationStore: defaults.string(forKey: Self.baselinePunctuationDefaultsKey)
                ?? defaults.string(forKey: KeymapPreferences.includePunctuationStoreKey)
                ?? "{}"
        )
        self.bindingStore = bindingStore
        self.displayContextStore = displayContextStore
        self.recognitionService = recognitionService
        self.initialKeyboardEventsProvider = initialKeyboardEventsProvider
    }

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

        let initialEvents = initialKeyboardEventsProvider()
        guard !initialEvents.isEmpty else { return }

        Task { @MainActor in
            for event in initialEvents {
                await handleNewKeyboard(event, showFeedback: false)
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

    private func handleNewKeyboard(_ event: HIDDeviceMonitor.HIDKeyboardEvent, showFeedback: Bool = true) async {
        let vidPidKey = event.vidPidKey

        // Deduplicate while connected (don't re-prompt for already-connected device)
        guard !connectedVIDPIDs.contains(vidPidKey) else { return }
        connectedVIDPIDs.insert(vidPidKey)

        // Check for existing accepted binding → auto-switch silently
        if let binding = await bindingStore.binding(
            vendorID: event.vendorID,
            productID: event.productID
        ) {
            AppLogger.shared.log("🔌 [AutoDetect] Known keyboard \(binding.keyboardName) — auto-switching to \(binding.layoutId)")
            upsertConnectedKeyboard(
                ConnectedKeyboard(
                    event: event,
                    keyboardName: binding.keyboardName,
                    manufacturer: nil,
                    layoutId: binding.layoutId,
                    qmkPath: nil,
                    source: .override,
                    matchType: .exactVIDPID,
                    confidence: .high,
                    status: .remembered
                ),
                makeActive: true
            )
            UserDefaults.standard.set(binding.layoutId, forKey: LayoutPreferences.layoutIdKey)
            if showFeedback {
                SoundPlayer.shared.playDeviceConnectedSound()
                showAutoSwitchToast(keyboardName: binding.keyboardName)
            }
            return
        }

        // No binding → try to recognize
        guard let result = await recognitionService.recognize(event: event) else {
            AppLogger.shared.log("🔌 [AutoDetect] No keyboard match for \(event.productName) (\(vidPidKey))")
            upsertConnectedKeyboard(
                ConnectedKeyboard(
                    event: event,
                    keyboardName: event.productName,
                    detectedKeyboardName: nil,
                    manufacturer: nil,
                    layoutId: nil,
                    qmkPath: nil,
                    source: nil,
                    matchType: nil,
                    confidence: nil,
                    status: .unrecognized
                ),
                makeActive: true
            )
            return
        }

        recognitionResultsByKeyboardID[event.id] = result

        AppLogger.shared.log(
            "🔌 [AutoDetect] Recognized \(result.keyboardName) (built-in: \(result.isBuiltIn), path: \(result.qmkPath ?? "none"), source: \(result.source.rawValue), match: \(result.matchType.rawValue))"
        )

        let keyboardStatus: ConnectedKeyboard.Status
        if result.confidence == .low {
            keyboardStatus = .possibleMatch
        } else if result.isBuiltIn {
            keyboardStatus = .suggested
        } else {
            keyboardStatus = .importRequired
        }

        upsertConnectedKeyboard(
            ConnectedKeyboard(
                event: event,
                keyboardName: result.confidence == .low ? event.productName : result.keyboardName,
                detectedKeyboardName: result.keyboardName,
                manufacturer: result.manufacturer,
                layoutId: result.layoutId,
                qmkPath: result.qmkPath,
                source: result.source,
                matchType: result.matchType,
                confidence: result.confidence,
                status: keyboardStatus
            ),
            makeActive: result.confidence == .high
        )

        if result.confidence == .low {
            AppLogger.shared.log("🔌 [AutoDetect] Keeping possible match for review only: \(event.productName) → \(result.keyboardName)")
            return
        }

        if result.isBuiltIn, let layoutId = result.layoutId {
            UserDefaults.standard.set(layoutId, forKey: LayoutPreferences.layoutIdKey)
        }

        // Show confirmation toast
        if showFeedback {
            SoundPlayer.shared.playDeviceConnectedSound()
            pendingResult = result
            toastKeyboardName = result.keyboardName
            toastMode = result.isBuiltIn ? .rememberKeyboard : .importKeyboard
            toastConfidence = result.confidence
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                showingToast = true
            }
            scheduleAutoDismiss(seconds: 8)
        }
    }

    private func handleKeyboardDisconnected(_ event: HIDDeviceMonitor.HIDKeyboardEvent) {
        connectedVIDPIDs.remove(event.vidPidKey)
        recognitionResultsByKeyboardID.removeValue(forKey: event.id)
        connectedKeyboards.removeAll { $0.id == event.id }
        if activeKeyboardID == event.id {
            let nextKeyboard = connectedKeyboards.last(where: \.canActivateOverlay)
            activeKeyboardID = nextKeyboard?.id
            if let layoutId = nextKeyboard?.layoutId {
                UserDefaults.standard.set(layoutId, forKey: LayoutPreferences.layoutIdKey)
            }
        }
        SoundPlayer.shared.playDeviceDisconnectedSound()
    }

    // MARK: - User Actions

    func acceptDetection() {
        if toastMode == .importFailed {
            presentKeyboardSearch(for: pendingResult?.deviceEvent.id)
            clearToast(cancelImport: false)
            return
        }

        guard let result = pendingResult else { return }
        autoDismissTask?.cancel()

        if result.isBuiltIn, let layoutId = result.layoutId {
            // Built-in layout is already selected on connect; accept persists it.
            saveBinding(result: result, layoutId: layoutId)
            markKeyboardAsRemembered(eventID: result.deviceEvent.id, layoutId: layoutId)
            AppLogger.shared.log("🔌 [AutoDetect] Accepted built-in layout: \(layoutId)")
            clearToast(cancelImport: false)
        } else {
            // QMK import needed — run inline
            performQMKImport(result: result)
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                showingToast = true
            }
        }
    }

    func dismissToast() {
        clearToast(cancelImport: true)
    }

    func selectKeyboard(_ keyboardID: String) {
        guard let keyboard = connectedKeyboards.first(where: { $0.id == keyboardID }) else { return }
        activeKeyboardID = keyboardID

        if let layoutId = keyboard.layoutId {
            UserDefaults.standard.set(layoutId, forKey: LayoutPreferences.layoutIdKey)
        } else if keyboard.status == .importRequired,
                  let result = recognitionResultsByKeyboardID[keyboardID]
        {
            pendingResult = result
            toastKeyboardName = result.keyboardName
            toastMode = .importKeyboard
            toastConfidence = result.confidence
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                showingToast = true
            }
            scheduleAutoDismiss(seconds: 8)
        } else if keyboard.status == .possibleMatch || keyboard.status == .unrecognized {
            presentKeyboardSearch(for: keyboardID)
        }
    }

    func presentKeyboardSearch(for keyboardID: String? = nil) {
        let keyboard = keyboardID.flatMap { id in
            connectedKeyboards.first(where: { $0.id == id })
        } ?? activeKeyboard.flatMap { active in
            connectedKeyboards.first(where: { $0.id == active.id })
        }
        keyboardSearchQuery = keyboard?.event.productName ?? keyboard?.keyboardName ?? ""
        isKeyboardSearchPresented = true
    }

    func dismissKeyboardSearch() {
        isKeyboardSearchPresented = false
    }

    func rememberCurrentLayoutSelection(layoutId: String) {
        guard let keyboard = activeKeyboard else { return }

        let binding = DeviceLayoutBindingStore.Binding(
            vendorProductKey: keyboard.vidPidKey,
            layoutId: layoutId,
            keyboardName: keyboard.keyboardName,
            acceptedAt: Date()
        )

        Task {
            do {
                try await bindingStore.saveBinding(binding)
            } catch {
                AppLogger.shared.warn("🔌 [AutoDetect] Failed to save binding for \(keyboard.keyboardName): \(error.localizedDescription)")
            }
        }

        markKeyboardAsRemembered(eventID: keyboard.id, layoutId: layoutId)
    }

    func overlayDisplayContextDidChange(
        layoutId: String,
        keymapId: String,
        includePunctuationStore: String
    ) {
        guard let keyboard = activeKeyboard, keyboard.canActivateOverlay else {
            updateBaselineDisplayContext(
                layoutId: layoutId,
                keymapId: keymapId,
                includePunctuationStore: includePunctuationStore
            )
            return
        }

        let context = KeyboardDisplayContextStore.Context(
            vendorProductKey: keyboard.vidPidKey,
            layoutId: layoutId,
            keymapId: keymapId,
            includePunctuationStore: includePunctuationStore,
            keyboardName: keyboard.keyboardName,
            updatedAt: Date()
        )

        Task {
            do {
                try await displayContextStore.saveContext(context)
            } catch {
                AppLogger.shared.warn("🔌 [AutoDetect] Failed to save display context for \(keyboard.keyboardName): \(error.localizedDescription)")
            }
        }
    }

    func activeKeyboardDidChange(
        from previousKeyboardID: String?,
        to newKeyboardID: String?,
        currentLayoutId: String,
        currentKeymapId: String,
        includePunctuationStore: String
    ) async -> KeyboardDisplayContextStore.Context? {
        if let previousKeyboardID,
           activeKeyboardID != previousKeyboardID,
           let previousKeyboard = connectedKeyboards.first(where: { $0.id == previousKeyboardID }),
           previousKeyboard.canActivateOverlay
        {
            let context = KeyboardDisplayContextStore.Context(
                vendorProductKey: previousKeyboard.vidPidKey,
                layoutId: currentLayoutId,
                keymapId: currentKeymapId,
                includePunctuationStore: includePunctuationStore,
                keyboardName: previousKeyboard.keyboardName,
                updatedAt: Date()
            )

            do {
                try await displayContextStore.saveContext(context)
            } catch {
                AppLogger.shared.warn("🔌 [AutoDetect] Failed to save context for \(previousKeyboard.keyboardName): \(error.localizedDescription)")
            }
        }

        guard let newKeyboardID,
              let newKeyboard = connectedKeyboards.first(where: { $0.id == newKeyboardID }),
              newKeyboard.canActivateOverlay
        else {
            return KeyboardDisplayContextStore.Context(
                vendorProductKey: "__baseline__",
                layoutId: baselineDisplayContext.layoutId,
                keymapId: baselineDisplayContext.keymapId,
                includePunctuationStore: baselineDisplayContext.includePunctuationStore,
                keyboardName: "Current Keyboard",
                updatedAt: Date()
            )
        }

        return await displayContextStore.context(vendorProductKey: newKeyboard.vidPidKey)
    }

    func forgetKeyboard(_ keyboardID: String) {
        guard let keyboard = connectedKeyboards.first(where: { $0.id == keyboardID }) else { return }

        Task {
            do {
                try await bindingStore.removeBinding(
                    vendorID: keyboard.event.vendorID,
                    productID: keyboard.event.productID
                )
            } catch {
                AppLogger.shared.warn("🔌 [AutoDetect] Failed to remove binding for \(keyboard.keyboardName): \(error.localizedDescription)")
            }

            do {
                try await displayContextStore.removeContext(vendorProductKey: keyboard.vidPidKey)
            } catch {
                AppLogger.shared.warn("🔌 [AutoDetect] Failed to remove display context for \(keyboard.keyboardName): \(error.localizedDescription)")
            }
        }

        if let result = recognitionResultsByKeyboardID[keyboardID] {
            if result.confidence == .low {
                updateKeyboardStatus(
                    eventID: keyboardID,
                    status: .possibleMatch,
                    layoutId: result.layoutId,
                    confidence: result.confidence
                )
            } else if result.isBuiltIn {
                updateKeyboardStatus(
                    eventID: keyboardID,
                    status: .suggested,
                    layoutId: result.layoutId,
                    confidence: result.confidence
                )
            } else {
                updateKeyboardStatus(
                    eventID: keyboardID,
                    status: .importRequired,
                    layoutId: nil,
                    confidence: result.confidence
                )
            }
        } else {
            updateKeyboardStatus(
                eventID: keyboardID,
                status: .unrecognized,
                layoutId: nil,
                confidence: nil
            )
        }
    }

    var activeKeyboard: ConnectedKeyboard? {
        guard let activeKeyboardID else { return nil }
        return connectedKeyboards.first(where: { $0.id == activeKeyboardID })
    }

    private func clearToast(cancelImport: Bool) {
        autoDismissTask?.cancel()
        if cancelImport {
            importTask?.cancel()
        }
        withAnimation(.easeOut(duration: 0.25)) {
            showingToast = false
        }
        pendingResult = nil
        toastErrorMessage = nil
    }

    // MARK: - Helpers

    private func showAutoSwitchToast(keyboardName: String) {
        toastKeyboardName = keyboardName
        toastMode = .autoSwitch
        toastConfidence = .high
        toastErrorMessage = nil
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
                try await bindingStore.saveBinding(binding)
            } catch {
                AppLogger.shared.warn("🔌 [AutoDetect] Failed to save binding for \(result.keyboardName): \(error.localizedDescription)")
            }
        }
    }

    private func upsertConnectedKeyboard(_ keyboard: ConnectedKeyboard, makeActive: Bool) {
        if let existingIndex = connectedKeyboards.firstIndex(where: { $0.id == keyboard.id }) {
            connectedKeyboards[existingIndex] = keyboard
        } else {
            connectedKeyboards.append(keyboard)
        }

        if makeActive {
            activeKeyboardID = keyboard.id
        }
    }

    private func markKeyboardAsRemembered(eventID: String, layoutId: String) {
        guard let index = connectedKeyboards.firstIndex(where: { $0.id == eventID }) else { return }
        connectedKeyboards[index].layoutId = layoutId
        connectedKeyboards[index].status = .remembered
        connectedKeyboards[index].confidence = .high
        connectedKeyboards[index].detectedKeyboardName = connectedKeyboards[index].keyboardName
    }

    private func updateKeyboardStatus(
        eventID: String,
        status: ConnectedKeyboard.Status,
        layoutId: String?,
        confidence: KeyboardDetectionIndex.Confidence?
    ) {
        guard let index = connectedKeyboards.firstIndex(where: { $0.id == eventID }) else { return }
        connectedKeyboards[index].layoutId = layoutId
        connectedKeyboards[index].status = status
        connectedKeyboards[index].confidence = confidence
    }

    private func updateBaselineDisplayContext(
        layoutId: String,
        keymapId: String,
        includePunctuationStore: String
    ) {
        let updatedContext = BaselineDisplayContext(
            layoutId: layoutId,
            keymapId: keymapId,
            includePunctuationStore: includePunctuationStore
        )
        guard updatedContext != baselineDisplayContext else { return }

        baselineDisplayContext = updatedContext
        let defaults = UserDefaults.standard
        defaults.set(layoutId, forKey: Self.baselineLayoutDefaultsKey)
        defaults.set(keymapId, forKey: Self.baselineKeymapDefaultsKey)
        defaults.set(includePunctuationStore, forKey: Self.baselinePunctuationDefaultsKey)
    }

    // MARK: - QMK Import

    private func performQMKImport(result: DeviceRecognitionService.RecognitionResult) {
        guard let qmkPath = result.qmkPath else {
            AppLogger.shared.warn("🔌 [AutoDetect] Missing QMK path for '\(result.keyboardName)'")
            return
        }

        toastKeyboardName = result.keyboardName
        toastMode = .importingKeyboard
        toastConfidence = result.confidence
        toastErrorMessage = nil

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
                markKeyboardAsRemembered(eventID: result.deviceEvent.id, layoutId: parseResult.layout.id)
                AppLogger.shared.log("🔌 [AutoDetect] Imported and selected QMK layout: \(layoutName)")
                toastMode = .importSucceeded
                toastErrorMessage = nil
                scheduleAutoDismiss(seconds: 3)

            } catch is CancellationError {
                AppLogger.shared.log("🔌 [AutoDetect] QMK import cancelled for '\(result.keyboardName)'")
            } catch {
                AppLogger.shared.warn("🔌 [AutoDetect] QMK import failed for '\(result.keyboardName)': \(error.localizedDescription)")
                toastMode = .importFailed
                toastErrorMessage = error.localizedDescription
                toastConfidence = result.confidence
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                    showingToast = true
                }
            }
        }
    }
}
