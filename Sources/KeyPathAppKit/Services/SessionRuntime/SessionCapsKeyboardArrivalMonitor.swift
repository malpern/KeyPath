import Foundation
import IOKit

/// When the worker next reconciles its Caps fleet. Arrivals pull the check
/// forward: a keyboard plugged in should be mapped before its first Caps press,
/// not up to one backstop interval later.
struct SessionCapsCheckSchedule: Equatable {
    /// The steady backstop while every keyboard's mapping stays verified.
    static let backstop: TimeInterval = 2
    /// The pause after each check right after an arrival. hidutil can list a new
    /// event service a moment after IOKit reports it.
    static let afterArrival: TimeInterval = 0.25
    /// How long arrival checks stay fast.
    static let arrivalWindow: TimeInterval = 3

    private(set) var fastUntil: Date = .distantPast
    private(set) var arrivalPending = false

    mutating func keyboardArrived(at now: Date) {
        arrivalPending = true
        fastUntil = now.addingTimeInterval(Self.arrivalWindow)
    }

    /// Whether a fleet check should start now. `lastCheck` is when the previous
    /// check finished, so fast checks still leave the HID queue idle between them.
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
    private let emitsKeyboardUsages: (UInt64) -> Bool?
    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var source: CFRunLoopSource?

    /// `emitsKeyboardUsages` is the same predicate the lease uses to group a
    /// keyboard's interfaces; injectable for tests.
    init(emitsKeyboardUsages: @escaping (UInt64) -> Bool? = SessionCapsHIDUtilTransport.serviceEmitsKeyboardUsages,
         onArrival: @escaping () -> Void)
    {
        self.emitsKeyboardUsages = emitsKeyboardUsages
        self.onArrival = onArrival
    }

    func start() -> Bool {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return false }
        self.port = port
        guard let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
            stop()
            return false
        }
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
        var registryIDs: [UInt64] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            // An unreadable ID still counts: the arrival is reported, and the
            // reconcile decides whether there is anything to map.
            registryIDs.append(IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS ? id : 0)
        }
        if report { reportArrivals(registryIDs) }
    }

    /// Fails open: a service whose keyboard capability can't be read yet is still
    /// an arrival, because one extra inventory read is cheap and a missed one
    /// leaves the keyboard unmapped until the backstop.
    func reportArrivals(_ registryIDs: [UInt64]) {
        let arrived = registryIDs.contains { id in id == 0 || emitsKeyboardUsages(id) != false }
        if arrived { onArrival() }
    }
}
