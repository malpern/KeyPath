import CoreGraphics
import Foundation
import IOKit.hid
import KeyPathCore
import KeyPathPermissions

/// Counts which keyboard each key came from, and changes nothing else
/// (ADR-048, rollout step 2). Keys reach the engine exactly as they do with the
/// switch off; this only feeds `KeyboardAttributionMatcher` and logs totals, so
/// the no-match and fallback rates can be measured before any rule depends on
/// them.
///
/// Pure bookkeeping, kept apart from IOKit so it can be tested. Tap events
/// wait in order until the matcher can decide them, as a held key would; the
/// caller passes the current time on every call.
struct KeyboardAttributionLog {
    struct Counts: Equatable {
        var credited: UInt64 = 0
        var noMatch: UInt64 = 0
        var ambiguous: UInt64 = 0
        var heldOnSeveralKeyboards: UInt64 = 0
        var pressNotCredited: UInt64 = 0
        /// Waiting events pushed out by `pendingLimit`; should stay zero.
        var dropped: UInt64 = 0

        var fellBack: UInt64 {
            noMatch + ambiguous + heldOnSeveralKeyboards + pressNotCredited
        }
    }

    /// Far more than the matcher can keep waiting: each event waits at most
    /// the look-ahead (5 ms).
    static let pendingLimit = 64

    private var matcher: KeyboardAttributionMatcher
    private(set) var pending: [KeyboardAttributionMatcher.TapEvent] = []
    private(set) var counts = Counts()
    /// Keyboards at least one event was credited to.
    private(set) var creditedKeyboards: Set<UInt64> = []
    private var latestTapNs: UInt64 = 0

    init(configuration: KeyboardAttributionMatcher.Configuration = .init()) {
        matcher = KeyboardAttributionMatcher(configuration: configuration)
    }

    mutating func record(_ value: KeyboardAttributionMatcher.HIDValue, nowNs: UInt64) {
        matcher.record(value)
        resolve(nowNs: nowNs)
    }

    mutating func observe(_ event: KeyboardAttributionMatcher.TapEvent, nowNs: UInt64) {
        // The matcher needs tap events in time order. Timestamps from the tap
        // are not guaranteed monotonic, so a late one is clamped rather than
        // trusted.
        latestTapNs = max(latestTapNs, event.timeNs)
        if pending.count >= Self.pendingLimit {
            pending.removeFirst()
            counts.dropped += 1
        }
        pending.append(.init(usage: event.usage, isDown: event.isDown, isRepeat: event.isRepeat, timeNs: latestTapNs))
        resolve(nowNs: nowNs)
    }

    /// Decides waiting events in order; stops at the first that must still wait.
    mutating func resolve(nowNs: UInt64) {
        while let first = pending.first {
            switch matcher.attribute(first, nowNs: nowNs) {
            case .wait:
                return
            case let .keyboard(device):
                counts.credited += 1
                creditedKeyboards.insert(device)
            case .fallback(.noMatch): counts.noMatch += 1
            case .fallback(.ambiguous): counts.ambiguous += 1
            case .fallback(.heldOnSeveralKeyboards): counts.heldOnSeveralKeyboards += 1
            case .fallback(.pressNotCredited): counts.pressNotCredited += 1
            }
            pending.removeFirst()
        }
    }

    mutating func removeDevice(_ device: UInt64) {
        matcher.removeDevice(device)
    }

    /// Totals only: no key, usage or timing is ever logged.
    func summary() -> String {
        let c = counts
        return "credited \(c.credited), fell back \(c.fellBack) (no match \(c.noMatch), "
            + "two keyboards \(c.ambiguous), held on several \(c.heldOnSeveralKeyboards), "
            + "press not credited \(c.pressNotCredited)), dropped \(c.dropped), "
            + "keyboards \(creditedKeyboards.count)"
    }
}

/// The unit of `CGEvent.timestamp`, which Apple does not document. Measured
/// once, from the first tap event, against the current time in both units.
enum KeyboardAttributionTapClock: Equatable {
    case nanoseconds
    case machTicks
    case unusable

    /// A tap event arrives within milliseconds of its timestamp, so read in
    /// the right unit it lands within a second of now. On a 1:1 timebase both
    /// readings agree and nanoseconds wins, which is the same thing.
    static func classify(eventTimestamp: UInt64, nowNs: UInt64, ticksToNs: (UInt64) -> UInt64) -> Self {
        func near(_ a: UInt64, _ b: UInt64) -> Bool {
            (a > b ? a - b : b - a) < 1_000_000_000
        }
        if near(eventTimestamp, nowNs) { return .nanoseconds }
        if near(ticksToNs(eventTimestamp), nowNs) { return .machTicks }
        return .unusable
    }
}

/// Watches every keyboard through IOHIDManager on the worker's run loop and
/// feeds `KeyboardAttributionLog`. Both callbacks share that run loop with the
/// tap, so nothing here locks or blocks.
@MainActor
final class KeyboardAttributionMonitor {
    nonisolated static let enabledKey = "keypath.session.keyboardAttribution.logOnly.v1"
    static let summaryIntervalNs: UInt64 = 600 * 1_000_000_000

    nonisolated static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    private var log = KeyboardAttributionLog()
    private var manager: IOHIDManager?
    private var tapClock: KeyboardAttributionTapClock?
    private var lastSummaryNs: UInt64
    private var lastSummaryCounts = KeyboardAttributionLog.Counts()
    private nonisolated static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    private init() {
        lastSummaryNs = Self.nowNs()
    }

    /// Nil when the switch is off, Input Monitoring is missing, or HID cannot
    /// be opened. Each refusal is logged once; the worker carries on unchanged.
    static func startIfEnabled() -> KeyboardAttributionMonitor? {
        guard isEnabled() else { return nil }
        guard SystemStateProvider.shared.keyPathInputMonitoringStatus() == .granted else {
            AppLogger.shared.log("⌨️ [Attribution] On, but Input Monitoring is not granted; not attributing")
            return nil
        }
        let monitor = KeyboardAttributionMonitor()
        guard monitor.open() else {
            AppLogger.shared.warn("⌨️ [Attribution] Could not open keyboards; not attributing")
            return nil
        }
        AppLogger.shared.log("⌨️ [Attribution] Log-only attribution started")
        return monitor
    }

    private func open() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<KeyboardAttributionMonitor>.fromOpaque(context).takeUnretainedValue().receive(value)
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<KeyboardAttributionMonitor>.fromOpaque(context).takeUnretainedValue()
                    .log.removeDevice(KeyboardAttributionMonitor.registryID(device))
            }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            Self.detach(manager)
            return false
        }
        self.manager = manager
        return true
    }

    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usage = IOHIDElementGetUsage(element)
        // Page 7 keys and modifiers; 0–3 are "no event" and error codes.
        guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad), usage >= 4, usage <= 0xE7 else { return }
        let device = IOHIDElementGetDevice(element)
        log.record(.init(device: Self.registryID(device), usage: usage,
                         isDown: IOHIDValueGetIntegerValue(value) != 0,
                         timeNs: Self.ticksToNs(IOHIDValueGetTimeStamp(value))),
                   nowNs: Self.nowNs())
    }

    /// Called from the tap for every physical key event it sees, after the
    /// worker's own output and software keyboards are filtered out.
    func observe(type: CGEventType, event: CGEvent, usage: UInt32) {
        let isDown: Bool
        let isRepeat: Bool
        switch type {
        case .keyDown:
            isDown = true
            isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        case .keyUp:
            isDown = false
            isRepeat = false
        case .flagsChanged:
            guard SessionKeyMap.isModifier(usage) else { return }
            isDown = event.flags.rawValue & SessionKeyMap.deviceModifierFlag(for: usage) != 0
            isRepeat = false
        default:
            return
        }
        let now = Self.nowNs()
        // Classified from events until one fits; a single late or odd event
        // must not turn attribution off for the whole run.
        if tapClock == nil || tapClock == .unusable {
            let clock = KeyboardAttributionTapClock.classify(eventTimestamp: event.timestamp, nowNs: now,
                                                             ticksToNs: Self.ticksToNs)
            if clock == .unusable, tapClock == nil {
                AppLogger.shared.warn("⌨️ [Attribution] A tap timestamp fits no known unit; skipping until one does")
            }
            tapClock = clock
        }
        let timeNs: UInt64
        switch tapClock {
        case .nanoseconds: timeNs = event.timestamp
        case .machTicks: timeNs = Self.ticksToNs(event.timestamp)
        case .unusable, nil: return
        }
        log.observe(.init(usage: usage, isDown: isDown, isRepeat: isRepeat, timeNs: timeNs), nowNs: now)
    }

    /// From the worker's 5 ms tick: decides events whose look-ahead has passed
    /// and logs totals every ten minutes when they changed.
    func tick() {
        let now = Self.nowNs()
        log.resolve(nowNs: now)
        guard now - lastSummaryNs >= Self.summaryIntervalNs else { return }
        lastSummaryNs = now
        guard log.counts != lastSummaryCounts else { return }
        lastSummaryCounts = log.counts
        AppLogger.shared.log("⌨️ [Attribution] \(log.summary())")
    }

    func stop() {
        if log.counts != KeyboardAttributionLog.Counts() {
            AppLogger.shared.log("⌨️ [Attribution] Final: \(log.summary())")
        }
        if let manager {
            Self.detach(manager)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    /// The callbacks hold an unretained pointer to the monitor, so they are
    /// cleared before it can be freed, not just unscheduled.
    private static func detach(_ manager: IOHIDManager) {
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    private nonisolated static func registryID(_ device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        _ = IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }

    private nonisolated static func ticksToNs(_ ticks: UInt64) -> UInt64 {
        ticks.multipliedReportingOverflow(by: timebase.numer).partialValue / timebase.denom
    }

    private nonisolated static func nowNs() -> UInt64 {
        ticksToNs(mach_absolute_time())
    }
}
