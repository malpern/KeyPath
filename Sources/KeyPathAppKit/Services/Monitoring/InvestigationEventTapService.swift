@preconcurrency import AppKit
import Foundation
import KeyPathCore

@MainActor
final class InvestigationEventTapService {
    static let shared = InvestigationEventTapService()

    private var observer: ObservingEventTap?
    private var isStarted = false

    func startIfNeeded() {
        guard !TestEnvironment.isRunningTests else { return }
        guard !isStarted else { return }
        // Diagnostic only: runs when listen access already exists, as before, so it
        // never prompts and is not switched on for everyone by the pass-through fallback.
        guard CGPreflightListenEventAccess() else { return }

        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        observer = ObservingEventTap.start(
            place: .tailAppendEventTap,
            events: CGEventMask(eventMask),
            threadName: "com.keypath.investigation-tap"
        ) { [weak self] type, event in
            guard let copy = event.copy() else { return }
            let observedAt = Date() // on the tap thread, so a busy main thread cannot skew it
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handleEvent(copy, type: type, observedAt: observedAt) }
            }
        }
        guard observer != nil else {
            AppLogger.shared.error("❌ [InvestigationEventTap] Failed to create investigation event tap")
            return
        }
        isStarted = true

        AppLogger.shared.debug("[INVESTIGATION] SystemKeyEvent tap_started location=cgSessionEventTap")
    }

    func stop() {
        guard isStarted else { return }
        observer?.stop()
        observer = nil

        isStarted = false
        AppLogger.shared.debug("[INVESTIGATION] SystemKeyEvent tap_stopped")
    }

    private func handleEvent(_ event: CGEvent, type: CGEventType, observedAt: Date) {
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let observed = InvestigationSystemKeyEvent(
            key: DuplicateInvestigationSupport.keyName(forKeyCode: keyCode),
            keyCode: keyCode,
            eventType: eventTypeName(type),
            isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) == 1,
            flagsRawValue: event.flags.rawValue,
            sourcePID: sourcePID(from: event),
            observedAt: observedAt
        )

        Task.detached(priority: .utility) {
            let correlation = await DuplicateKeyInvestigationTracker.shared.recordSystemEvent(observed)
            if correlation.suggestsUnmatchedAutorepeat {
                if DuplicateInvestigationSupport.isEnabled() {
                    AppLogger.shared.info(DuplicateInvestigationSupport.makeAutorepeatMismatchLog(correlation))
                }
                await StuckKeyRecoveryService.shared.handleAutorepeatMismatch(correlation)
            }
        }
    }

    private func eventTypeName(_ type: CGEventType) -> String {
        switch type {
        case .keyDown:
            "keyDown"
        case .keyUp:
            "keyUp"
        case .flagsChanged:
            "flagsChanged"
        default:
            "event-\(type.rawValue)"
        }
    }

    private func sourcePID(from event: CGEvent) -> Int64? {
        let raw = event.getIntegerValueField(.eventSourceUnixProcessID)
        return raw > 0 ? raw : nil
    }
}
