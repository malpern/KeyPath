// Keyboard attribution spike (see README.md).
//
// Question: can KeyPath tell which physical keyboard each key came from, when
// it reads keys through a CGEventTap (which merges all keyboards)?
//
// Approach under test: also watch every keyboard through IOHIDManager (which
// names the device, but needs Input Monitoring) and match each tap event to
// the HID event for the same key and direction by timestamp.
//
// This records both streams, then matches offline when it stops, so the order
// in which the two callbacks arrive does not matter. It changes no input:
// the tap is listen-only and HID devices are opened without seizing.
//
// Build: swiftc -O -target arm64-apple-macos27.0 -o /tmp/kb-attribution main.swift
// Run:   /tmp/kb-attribution [--seconds 120] [--csv out.csv]
//        Type on each keyboard (alternate, overlap, hold a key to repeat).
//        Ctrl-C or the timeout ends it and prints the report.

import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.hid

// MARK: - Raw records

struct HIDRecord {
    let deviceID: UInt64
    let keyCode: Int // macOS virtual keycode, mapped from the HID usage
    let down: Bool
    let eventNs: UInt64 // IOHIDValue timestamp, converted to ns
    let receivedNs: UInt64 // when our callback ran
}

struct TapRecord {
    let keyCode: Int
    let down: Bool
    let autorepeat: Bool
    let eventRaw: UInt64 // CGEventGetTimestamp, unit to be determined
    let receivedNs: UInt64
}

var hidRecords: [HIDRecord] = []
var tapRecords: [TapRecord] = []
var deviceNames: [UInt64: String] = [:]
var unmappedHIDUsages = 0
var tapPort: CFMachPort?
var tapDisabledCount = 0 // macOS disabled the tap (timeout or secure input); events were lost

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
func ticksToNs(_ ticks: UInt64) -> UInt64 {
    ticks &* UInt64(timebase.numer) / UInt64(timebase.denom)
}

func nowNs() -> UInt64 {
    ticksToNs(mach_absolute_time())
}

// MARK: - HID usage (page 7) to macOS virtual keycode

let usageToKeyCode: [Int: Int] = [
    0x04: 0, 0x05: 11, 0x06: 8, 0x07: 2, 0x08: 14, 0x09: 3, 0x0A: 5, 0x0B: 4, 0x0C: 34,
    0x0D: 38, 0x0E: 40, 0x0F: 37, 0x10: 46, 0x11: 45, 0x12: 31, 0x13: 35, 0x14: 12,
    0x15: 15, 0x16: 1, 0x17: 17, 0x18: 32, 0x19: 9, 0x1A: 13, 0x1B: 7, 0x1C: 16, 0x1D: 6,
    0x1E: 18, 0x1F: 19, 0x20: 20, 0x21: 21, 0x22: 23, 0x23: 22, 0x24: 26, 0x25: 28,
    0x26: 25, 0x27: 29, 0x28: 36, 0x29: 53, 0x2A: 51, 0x2B: 48, 0x2C: 49, 0x2D: 27,
    0x2E: 24, 0x2F: 33, 0x30: 30, 0x31: 42, 0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43,
    0x37: 47, 0x38: 44, 0x4F: 124, 0x50: 123, 0x51: 125, 0x52: 126,
]

// MARK: - HID side

func deviceID(_ device: IOHIDDevice) -> UInt64 {
    var id: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
    return id
}

let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(hidManager, [
    kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
    kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
] as CFDictionary)

IOHIDManagerRegisterDeviceMatchingCallback(hidManager, { _, _, _, device in
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown"
    let id = deviceID(device)
    deviceNames[id] = name
    print("keyboard: \(name) [\(id)]")
}, nil)

IOHIDManagerRegisterInputValueCallback(hidManager, { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad) else { return }
    let usage = Int(IOHIDElementGetUsage(element))
    guard usage >= 0x04, usage <= 0xE7 else { return } // skip rollover/error usages
    guard let keyCode = usageToKeyCode[usage] else {
        unmappedHIDUsages += 1
        return
    }
    let device = IOHIDElementGetDevice(element)
    hidRecords.append(HIDRecord(
        deviceID: deviceID(device), keyCode: keyCode, down: IOHIDValueGetIntegerValue(value) != 0,
        eventNs: ticksToNs(IOHIDValueGetTimeStamp(value)), receivedNs: nowNs()
    ))
}, nil)

IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess {
    print("IOHIDManagerOpen failed (0x\(String(openResult, radix: 16))): grant Input Monitoring to this terminal app, then rerun.")
    exit(1)
}

// MARK: - Tap side (listen-only)

let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
    eventsOfInterest: CGEventMask(mask),
    callback: { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapDisabledCount += 1
            if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown || type == .keyUp {
            tapRecords.append(TapRecord(
                keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                down: type == .keyDown,
                autorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                eventRaw: event.timestamp, receivedNs: nowNs()
            ))
        }
        return Unmanaged.passUnretained(event)
    }, userInfo: nil
) else {
    print("CGEvent.tapCreate failed: grant Input Monitoring (listen) to this terminal app, then rerun.")
    exit(1)
}

tapPort = tap
CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

// MARK: - Matching and report

struct Match {
    let tapIndex: Int
    let deviceID: UInt64?
    let candidates: Int // distinct devices with a matching HID event in the window
    let latencyNs: Int64?
}

/// Match each non-repeat tap event to the closest unconsumed HID event for the
/// same key and direction whose time lies in [tap - window, tap + slack].
func match(tapTime: (TapRecord) -> UInt64, hidTime: (HIDRecord) -> UInt64,
           windowNs: UInt64, slackNs: UInt64) -> [Match]
{
    var used = Set<Int>()
    var lastDownDevice: [Int: UInt64] = [:]
    var results: [Match] = []
    for (i, tapEvent) in tapRecords.enumerated() {
        if tapEvent.autorepeat {
            // Repeats have no HID event: inherit the device that pressed the key.
            results.append(Match(tapIndex: i, deviceID: lastDownDevice[tapEvent.keyCode], candidates: -1, latencyNs: nil))
            continue
        }
        let t = tapTime(tapEvent)
        let lo = t > windowNs ? t - windowNs : 0
        let hi = t + slackNs
        var best: (index: Int, delta: Int64)?
        var devices = Set<UInt64>()
        for (j, h) in hidRecords.enumerated() where !used.contains(j)
            && h.keyCode == tapEvent.keyCode && h.down == tapEvent.down
        {
            let ht = hidTime(h)
            guard ht >= lo, ht <= hi else { continue }
            devices.insert(h.deviceID)
            let delta = Int64(bitPattern: t &- ht)
            if best == nil || abs(delta) < abs(best!.delta) { best = (j, delta) }
        }
        if let best {
            used.insert(best.index)
            let device = hidRecords[best.index].deviceID
            if tapEvent.down { lastDownDevice[tapEvent.keyCode] = device }
            results.append(Match(tapIndex: i, deviceID: device, candidates: devices.count, latencyNs: best.delta))
        } else {
            results.append(Match(tapIndex: i, deviceID: nil, candidates: 0, latencyNs: nil))
        }
    }
    return results
}

func percentile(_ values: [Int64], _ p: Double) -> Int64 {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
}

func report(_ label: String, _ matches: [Match]) {
    let fresh = matches.filter { $0.candidates >= 0 }
    let repeats = matches.filter { $0.candidates < 0 }
    let attributed = fresh.filter { $0.deviceID != nil }
    let ambiguous = fresh.filter { $0.candidates > 1 }
    let latencies = attributed.compactMap(\.latencyNs).map { $0 / 1000 }
    print("""

    == \(label)
    tap events (not repeats): \(fresh.count)
      attributed:   \(attributed.count) (\(fresh.isEmpty ? 0 : attributed.count * 100 / fresh.count)%)
      unattributed: \(fresh.count - attributed.count)
      ambiguous (2+ keyboards had a candidate): \(ambiguous.count)
    repeats: \(repeats.count), inherited a device: \(repeats.filter { $0.deviceID != nil }.count)
    tap minus HID time, µs: p50 \(percentile(latencies, 0.5)) p95 \(percentile(latencies, 0.95)) max \(latencies.max() ?? 0) min \(latencies.min() ?? 0)
    """)
    var perDevice: [UInt64: Int] = [:]
    for m in attributed {
        perDevice[m.deviceID!, default: 0] += 1
    }
    for (id, count) in perDevice.sorted(by: { $0.value > $1.value }) {
        print("  \(deviceNames[id] ?? "?") [\(id)]: \(count)")
    }
}

var csvPath: String?
var seconds = 120.0
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--seconds": seconds = Double(args.next() ?? "") ?? seconds
    case "--csv": csvPath = args.next()
    default: print("unknown argument \(arg)"); exit(2)
    }
}

func finish() -> Never {
    CGEvent.tapEnable(tap: tap, enable: false)
    print("\nHID key events: \(hidRecords.count) (unmapped usages skipped: \(unmappedHIDUsages)), tap key events: \(tapRecords.count)")
    if tapDisabledCount > 0 { print("WARNING: the tap was disabled \(tapDisabledCount) time(s); tap counts are incomplete") }
    // The event timestamps' clocks are not documented to agree, so report both
    // the event-timestamp match and the callback-arrival match.
    report("by event timestamps (CGEvent timestamp as ns vs HID timestamp)",
           match(tapTime: { $0.eventRaw }, hidTime: { $0.eventNs }, windowNs: 50_000_000, slackNs: 5_000_000))
    report("by callback arrival time (both mach_absolute_time)",
           match(tapTime: { $0.receivedNs }, hidTime: { $0.receivedNs }, windowNs: 50_000_000, slackNs: 50_000_000))
    if let csvPath {
        var lines = ["source,device,name,keycode,down,autorepeat,event,received"]
        for h in hidRecords {
            lines.append("hid,\(h.deviceID),\"\(deviceNames[h.deviceID] ?? "")\",\(h.keyCode),\(h.down),,\(h.eventNs),\(h.receivedNs)")
        }
        for t in tapRecords {
            lines.append("tap,,,\(t.keyCode),\(t.down),\(t.autorepeat),\(t.eventRaw),\(t.receivedNs)")
        }
        try? lines.joined(separator: "\n").write(toFile: csvPath, atomically: true, encoding: .utf8)
        print("raw events: \(csvPath)")
    }
    exit(0)
}

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler { finish() }
sigint.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finish() }

print("Recording for \(Int(seconds))s. Type on each keyboard; Ctrl-C to stop early. Key contents are not stored, only key codes.")
CFRunLoopRun()
