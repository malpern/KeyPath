import Foundation
import IOKit

/// When the worker next reconciles its Caps fleet. Arrivals pull the check
/// forward: a keyboard plugged in should be mapped before its first Caps press,
/// not up to one backstop interval later.
struct SessionCapsCheckSchedule: Equatable {
    /// The steady backstop while every keyboard's mapping stays verified.
    static let backstop: TimeInterval = 2
    /// How often to re-read inventory right after an arrival. hidutil can list a
    /// new event service a moment after IOKit reports it.
    static let afterArrival: TimeInterval = 0.25
    /// How long arrival checks stay fast.
    static let arrivalWindow: TimeInterval = 3

    private(set) var fastUntil: Date = .distantPast
    private(set) var arrivalPending = false

    mutating func keyboardArrived(at now: Date) {
        arrivalPending = true
        fastUntil = now.addingTimeInterval(Self.arrivalWindow)
    }

    /// Whether a fleet check should start now, given the last one's start time.
    func isDue(now: Date, lastCheck: Date) -> Bool {
        if arrivalPending { return true }
        let interval = now < fastUntil ? Self.afterArrival : Self.backstop
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// A check is starting; it covers every arrival reported so far.
    mutating func checkStarted() {
        arrivalPending = false
    }
}

/// Reports keyboard event services as they register, on the worker's main run
/// loop. It only schedules a check: eligibility, exclusions and all-keys-up are
/// decided by the fleet reconcile, exactly as for the backstop check.
@MainActor
final class SessionCapsKeyboardArrivalMonitor {
    private let onArrival: () -> Void
    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var source: CFRunLoopSource?

    init(onArrival: @escaping () -> Void) {
        self.onArrival = onArrival
    }

    func start() -> Bool {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault),
              let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
        else { return false }
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        let status = IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, IOServiceMatching("IOHIDEventService"),
            { context, iterator in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let monitor = Unmanaged<SessionCapsKeyboardArrivalMonitor>.fromOpaque(context).takeUnretainedValue()
                    monitor.drain(iterator, report: true)
                }
            },
            Unmanaged.passUnretained(self).toOpaque(), &iterator
        )
        guard status == KERN_SUCCESS else {
            stop()
            return false
        }
        // The first drain lists services already present and arms the
        // notification. Those are startup inventory, not arrivals.
        drain(iterator, report: false)
        return true
    }

    func stop() {
        if iterator != 0 { IOObjectRelease(iterator) }
        iterator = 0
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private func drain(_ iterator: io_iterator_t, report: Bool) {
        var arrived = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if report, Self.emitsKeyboardUsages(service) { arrived = true }
        }
        if arrived { onArrival() }
    }

    /// Any interface that can carry keyboard reports, including a board's shared
    /// N-key-rollover interface whose primary usage is not keyboard.
    private static func emitsKeyboardUsages(_ service: io_service_t) -> Bool {
        guard let pairs = IORegistryEntryCreateCFProperty(service, "DeviceUsagePairs" as CFString,
                                                          kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return false }
        return pairs.contains {
            ($0["DeviceUsagePage"] as? NSNumber)?.intValue == 1 && ($0["DeviceUsage"] as? NSNumber)?.intValue == 6
        }
    }
}
