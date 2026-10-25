import Foundation
import IOKit

/// A keyboard event service IOKit has just registered.
struct SessionCapsArrivedService: Hashable, Sendable {
    let registryEntryID: UInt64
    /// Nil when unreadable. A LocationID of 0 marks a virtual keyboard.
    let locationID: UInt32?
}

/// When the worker next reconciles its Caps fleet. An arrival pulls one check
/// forward. If that check's listing doesn't show the arrived keyboard yet, a few
/// more follow quickly, then the backstop takes over. A wake that re-registers
/// already-listed keyboards costs a single check.
struct SessionCapsCheckSchedule: Equatable {
    /// The steady backstop, measured between check starts.
    static let backstop: TimeInterval = 2
    /// The pause after each fast check finishes. hidutil can list a new event
    /// service a moment after IOKit reports it.
    static let afterArrival: TimeInterval = 0.25
    /// Fast checks an arrival may use while its keyboard is unlisted. Each check
    /// spawns several hidutil processes, so this is a count, not a duration.
    static let fastChecks = 6

    private(set) var arrivalPending = false
    /// Arrived keyboards hidutil has not listed yet.
    private(set) var unlisted: Set<SessionCapsArrivedService> = []
    private(set) var fastChecksLeft = 0

    /// Every arrival gets an immediate check. Only a service that reads as a
    /// keyboard and is not virtual can earn fast checks until hidutil lists it.
    /// Returns whether the arrival is tracked, which is what may be timed.
    @discardableResult
    mutating func keyboardArrived(at _: Date, keyboards: [SessionCapsArrivedService]) -> Bool {
        arrivalPending = true
        let real = keyboards.filter { $0.locationID != 0 }
        guard !real.isEmpty else { return false }
        unlisted.formUnion(real)
        fastChecksLeft = Self.fastChecks
        return true
    }

    func isDue(now: Date, lastStart: Date, lastEnd: Date) -> Bool {
        if arrivalPending { return true }
        if !unlisted.isEmpty, fastChecksLeft > 0 { return now.timeIntervalSince(lastEnd) >= Self.afterArrival }
        return now.timeIntervalSince(lastStart) >= Self.backstop
    }

    /// A check is starting; it covers every arrival reported so far. Returns the
    /// arrived keyboards it should look for in its listing.
    mutating func checkStarted() -> Set<SessionCapsArrivedService> {
        arrivalPending = false
        return unlisted
    }

    /// `resolved`: arrived keyboards the check found listed, or found gone.
    mutating func checkFinished(resolved: Set<SessionCapsArrivedService>) {
        unlisted.subtract(resolved)
        fastChecksLeft = max(0, fastChecksLeft - 1)
        if fastChecksLeft == 0 { unlisted = [] }
    }

    /// A check that produced no answer neither confirms nor refutes an arrival.
    /// Fast retries would only spawn hidutil again, so the backstop takes over.
    mutating func checkFailed() {
        unlisted = []
        fastChecksLeft = 0
    }

    /// The arrived keyboards a listing accounts for: listed under their own ID or
    /// as another interface at their LocationID, or no longer registered.
    static func resolved(_ arrived: Set<SessionCapsArrivedService>,
                         listed: [SessionCapsHIDUtilTransport.ServiceRow],
                         exists: (UInt64) -> Bool?) -> Set<SessionCapsArrivedService>
    {
        let ids = Set(listed.map(\.registryEntryID))
        let locations = Set(listed.compactMap(\.locationID).filter { $0 != 0 })
        return arrived.filter { service in
            if ids.contains(service.registryEntryID) { return true }
            if let location = service.locationID, locations.contains(location) { return true }
            return exists(service.registryEntryID) == false
        }
    }
}

/// Reports keyboard event services as they register, on the worker's main run
/// loop. It only schedules a check: eligibility, exclusions and all-keys-up are
/// decided by the fleet reconcile, exactly as for the backstop check.
@MainActor
final class SessionCapsKeyboardArrivalMonitor {
    private let onArrival: (_ keyboards: [SessionCapsArrivedService]) -> Void
    private let emitsKeyboardUsages: @Sendable (UInt64) -> Bool?
    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var source: CFRunLoopSource?

    /// `emitsKeyboardUsages` is the same predicate the lease uses to group a
    /// keyboard's interfaces; injectable for tests.
    init(emitsKeyboardUsages: @escaping @Sendable (UInt64) -> Bool? = SessionCapsHIDUtilTransport.serviceEmitsKeyboardUsages,
         onArrival: @escaping (_ keyboards: [SessionCapsArrivedService]) -> Void)
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
        var services: [SessionCapsArrivedService] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            // An unreadable ID still counts: the arrival is reported, and the
            // reconcile decides whether there is anything to map.
            let readable = IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS
            let location = IORegistryEntryCreateCFProperty(service, "LocationID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
            services.append(.init(registryEntryID: readable ? id : 0,
                                  locationID: location.flatMap { UInt32(exactly: $0.uint64Value) }))
        }
        guard report, !services.isEmpty else { return }
        // Classifying can walk the registry and parse report descriptors, once per
        // service in a batch. Keep that off the run loop the event tap shares.
        let classify = emitsKeyboardUsages
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let answers = Self.classify(services, with: classify)
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.port != nil else { return }
                    self.deliver(services, answers)
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    private nonisolated static func classify(_ services: [SessionCapsArrivedService],
                                             with emitsKeyboardUsages: (UInt64) -> Bool?) -> [Bool?]
    {
        services.map { $0.registryEntryID == 0 ? nil : emitsKeyboardUsages($0.registryEntryID) }
    }

    /// Classifies on the caller's thread; for tests.
    func reportArrivals(_ services: [SessionCapsArrivedService]) {
        deliver(services, Self.classify(services, with: emitsKeyboardUsages))
    }

    /// Fails open: a service whose keyboard capability can't be read yet still
    /// earns one pulled-forward check, so the keyboard isn't left for the backstop.
    /// Only services that read as keyboards are passed on, to be looked for.
    private func deliver(_ services: [SessionCapsArrivedService], _ answers: [Bool?]) {
        guard answers.contains(where: { $0 != false }) else { return }
        onArrival(zip(services, answers).filter { $0.1 == true }.map(\.0))
    }

    isolated deinit {
        stop()
    }
}
