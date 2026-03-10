import AppKit
import Foundation
import KeyPathCore

@MainActor
final class InvestigationEventTapService {
    static let shared = InvestigationEventTapService()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isStarted = false

    func startIfNeeded() {
        guard DuplicateInvestigationSupport.isEnabled() else { return }
        guard !TestEnvironment.isRunningTests else { return }
        guard !isStarted else { return }

        let eventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let service = Unmanaged<InvestigationEventTapService>.fromOpaque(refcon).takeUnretainedValue()
                service.handleEvent(event, type: type)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            AppLogger.shared.error("❌ [InvestigationEventTap] Failed to create investigation event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isStarted = true

        AppLogger.shared.debug("[INVESTIGATION] SystemKeyEvent tap_started location=cgSessionEventTap")
    }

    func stop() {
        guard isStarted else { return }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        isStarted = false
        AppLogger.shared.debug("[INVESTIGATION] SystemKeyEvent tap_stopped")
    }

    private func handleEvent(_ event: CGEvent, type: CGEventType) {
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let observed = InvestigationSystemKeyEvent(
            key: DuplicateInvestigationSupport.keyName(forKeyCode: keyCode),
            keyCode: keyCode,
            eventType: eventTypeName(type),
            isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) == 1,
            flagsRawValue: event.flags.rawValue,
            sourcePID: sourcePID(from: event),
            observedAt: Date()
        )

        Task.detached(priority: .utility) {
            let correlation = await DuplicateKeyInvestigationTracker.shared.recordSystemEvent(observed)
            AppLogger.shared.debug(DuplicateInvestigationSupport.makeSystemKeyEventLog(correlation))
            if correlation.suggestsUnmatchedAutorepeat {
                AppLogger.shared.debug(DuplicateInvestigationSupport.makeAutorepeatMismatchLog(correlation))
            }
        }
    }

    private func eventTypeName(_ type: CGEventType) -> String {
        switch type {
        case .keyDown:
            return "keyDown"
        case .keyUp:
            return "keyUp"
        case .flagsChanged:
            return "flagsChanged"
        default:
            return "event-\(type.rawValue)"
        }
    }

    private func sourcePID(from event: CGEvent) -> Int64? {
        let raw = event.getIntegerValueField(.eventSourceUnixProcessID)
        return raw > 0 ? raw : nil
    }
}
