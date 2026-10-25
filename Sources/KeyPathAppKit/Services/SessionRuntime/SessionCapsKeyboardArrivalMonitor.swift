import Foundation
import IOKit

/// When the worker next reconciles its Caps fleet. An arrival pulls one check
/// forward. Checks then stay fast only while a keyboard is waiting to be mapped,
/// so a wake that re-registers already-covered keyboards costs a single check.
struct SessionCapsCheckSchedule: Equatable {
    /// The steady backstop, measured between check starts.
    static let backstop: TimeInterval = 2
    /// The pause after each fast check finishes. hidutil can list a new event
    /// service a moment after IOKit reports it.
    static let afterArrival: TimeInterval = 0.25
    /// Fast checks after a recognised keyboard arrives, before any check reports.
    static let arrivalWindow: TimeInterval = 3
    /// The longest a waiting keyboard keeps checks fast, for example while keys
    /// held at plug-in block admission.
    static let waitLimit: TimeInterval = 30

    private(set) var arrivalPending = false
    private(set) var fastUntil: Date = .distantPast
    private(set) var arrivedAt: Date?

    /// `recognised`: the service reads as a keyboard. An unreadable one still gets
    /// its immediate check, but cannot open a fast window by itself.
    mutating func keyboardArrived(at now: Date, recognised: Bool) {
        arrivalPending = true
        guard recognised else { return }
        if arrivedAt == nil { arrivedAt = now }
        fastUntil = max(fastUntil, now.addingTimeInterval(Self.arrivalWindow))
    }

    func isDue(now: Date, lastStart: Date, lastEnd: Date) -> Bool {
        if arrivalPending { return true }
        if now < fastUntil { return now.timeIntervalSince(lastEnd) >= Self.afterArrival }
        return now.timeIntervalSince(lastStart) >= Self.backstop
    }

    /// A check is starting; it covers every arrival reported so far.
    mutating func checkStarted() {
        arrivalPending = false
    }

    /// `waiting`: eligible keyboards the check left unmapped that may still be
    /// admitted (not backing off after a failed write).
    mutating func checkFinished(at now: Date, waiting: Int) {
        guard waiting > 0 else {
            fastUntil = .distantPast
            arrivedAt = nil
            return
        }
        guard let arrivedAt, now < arrivedAt.addingTimeInterval(Self.waitLimit) else {
            fastUntil = .distantPast
            arrivedAt = nil
            return
        }
        fastUntil = max(fastUntil, now.addingTimeInterval(Self.afterArrival + Self.backstop))
    }
}

/// Reports keyboard event services as they register, on the worker's main run
/// loop. It only schedules a check: eligibility, exclusions and all-keys-up are
/// decided by the fleet reconcile, exactly as for the backstop check.
@MainActor
final class SessionCapsKeyboardArrivalMonitor {
    private let onArrival: (_ recognised: Bool) -> Void
    private let emitsKeyboardUsages: (UInt64) -> Bool?
    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var source: CFRunLoopSource?

    /// `emitsKeyboardUsages` is the same predicate the lease uses to group a
    /// keyboard's interfaces; injectable for tests.
    init(emitsKeyboardUsages: @escaping (UInt64) -> Bool? = SessionCapsHIDUtilTransport.serviceEmitsKeyboardUsages,
         onArrival: @escaping (_ recognised: Bool) -> Void)
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

    /// Fails open: a service whose keyboard capability can't be read yet still
    /// earns one pulled-forward check, so the keyboard isn't left for the backstop.
    func reportArrivals(_ registryIDs: [UInt64]) {
        let answers = registryIDs.map { $0 == 0 ? nil : emitsKeyboardUsages($0) }
        guard answers.contains(where: { $0 != false }) else { return }
        onArrival(answers.contains(true))
    }
}
