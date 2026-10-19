// Throwaway spike: can managed Caps Lock be read per-service from the HID event
// system instead of through a reserved CGEvent keycode (F18)?
//
// Prints one NDJSON line per observation, from three independent observers:
//   evsys  — IOHIDEventSystemClient (private SPI), post-filter keyboard events
//            with the sender (event-service registry ID) and HID timestamp.
//   hidmgr — IOHIDManager input values (public API), pre-filter device reports.
//   tap    — a listen-only CGEventTap at the session level.
// All times are nanoseconds on the mach continuous/absolute timebase so the
// three streams are directly comparable.
//
// Usage: caps-hid-usage-probe [--seconds N] [--sender 0xREGID]
//   --sender restricts evsys/hidmgr output to one event service / its device.
// Not product code. Build: swiftc -O -o probe main.swift

import ApplicationServices
import Carbon
import Darwin
import Foundation
import IOKit
import IOKit.hid

setvbuf(stdout, nil, _IOLBF, 0)

var seconds: Double = 30
var senderFilter: UInt64?
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--seconds": seconds = Double(args.next() ?? "") ?? seconds
    case "--sender": senderFilter = args.next().flatMap { UInt64($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
    default: FileHandle.standardError.write("unknown argument \(arg)\n".data(using: .utf8)!); exit(64)
    }
}

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
func ns(_ abs: UInt64) -> UInt64 { abs &* UInt64(timebase.numer) / UInt64(timebase.denom) }
func nowNS() -> UInt64 { ns(mach_absolute_time()) }

func emit(_ fields: [String: Any]) {
    var row = fields
    row["recv"] = nowNS()
    if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
}

// MARK: TCC

emit(["kind": "access",
      "listen": IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue,
      "post": IOHIDCheckAccess(kIOHIDRequestTypePostEvent).rawValue,
      "ax": AXIsProcessTrusted(),
      "secureInput": IsSecureEventInputEnabled()])

// MARK: IOHIDEventSystemClient (private SPI, resolved at runtime)

typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
typealias CreateWithType = @convention(c) (CFAllocator?, Int32, CFDictionary?) -> Unmanaged<AnyObject>?
typealias ScheduleQueue = @convention(c) (AnyObject, DispatchQueue) -> Void
typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
typealias EventCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
typealias RegisterCallback = @convention(c) (AnyObject, EventCallback, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
typealias Activate = @convention(c) (AnyObject) -> Void
typealias EventGetType = @convention(c) (UnsafeMutableRawPointer) -> UInt32
typealias EventGetInt = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Int
typealias EventGetU64 = @convention(c) (UnsafeMutableRawPointer) -> UInt64

let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
func sym<T>(_ name: String, _: T.Type) -> T? {
    guard let pointer = dlsym(iokit, name) else { return nil }
    return unsafeBitCast(pointer, to: T.self)
}

let kKeyboardEvent: UInt32 = 3
let fieldPage: UInt32 = (3 << 16) | 0
let fieldUsage: UInt32 = (3 << 16) | 1
let fieldDown: UInt32 = (3 << 16) | 2
let fieldRepeat: UInt32 = (3 << 16) | 3

let getType = sym("IOHIDEventGetType", EventGetType.self)!
let getInt = sym("IOHIDEventGetIntegerValue", EventGetInt.self)!
let getSender = sym("IOHIDEventGetSenderID", EventGetU64.self)!
let getTime = sym("IOHIDEventGetTimeStamp", EventGetU64.self)!

var eventClient: AnyObject?
let hidQueue = DispatchQueue(label: "probe.hid", qos: .userInteractive)
// Types: 0 admin, 1 monitor, 2 passive, 3 rate-controlled, 4 simple. Env EVSYS_TYPE picks one.
let clientType = Int32(ProcessInfo.processInfo.environment["EVSYS_TYPE"] ?? "4") ?? 4
let evCallback: EventCallback = { _, _, _, event in
    guard let event, getType(event) == kKeyboardEvent else { return }
    let sender = getSender(event)
    if let senderFilter, sender != senderFilter { return }
    emit(["kind": "evsys", "page": getInt(event, fieldPage), "usage": getInt(event, fieldUsage),
          "down": getInt(event, fieldDown), "repeat": getInt(event, fieldRepeat),
          "sender": String(sender, radix: 16), "t": ns(getTime(event))])
}
if let create = sym("IOHIDEventSystemClientCreateWithType", CreateWithType.self),
   let client = create(kCFAllocatorDefault, clientType, nil)?.takeRetainedValue() {
    sym("IOHIDEventSystemClientSetMatching", SetMatching.self)?(client, ["PrimaryUsagePage": 1, "PrimaryUsage": 6] as CFDictionary)
    sym("IOHIDEventSystemClientRegisterEventCallback", RegisterCallback.self)!(client, evCallback, nil, nil)
    sym("IOHIDEventSystemClientScheduleWithDispatchQueue", ScheduleQueue.self)!(client, hidQueue)
    sym("IOHIDEventSystemClientActivate", Activate.self)?(client)
    eventClient = client
    emit(["kind": "evsys", "client": "type\(clientType)"])
} else {
    emit(["kind": "evsys", "error": "CreateWithType(\(clientType)) returned nil"])
}

// MARK: IOHIDManager (public API, device reports before service filters)

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, ["PrimaryUsagePage": 1, "PrimaryUsage": 6] as CFDictionary)
IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    guard page == 7, usage >= 4, usage != 0xFFFFFFFF else { return }
    let device = IOHIDElementGetDevice(element)
    var deviceID: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &deviceID)
    emit(["kind": "hidmgr", "page": page, "usage": usage, "value": IOHIDValueGetIntegerValue(value),
          "device": String(deviceID, radix: 16), "t": ns(IOHIDValueGetTimeStamp(value))])
}, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
emit(["kind": "hidmgr", "open": IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))])
for device in (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [] {
    var id: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
    let capsElements = (IOHIDDeviceCopyMatchingElements(device, ["UsagePage": 7, "Usage": 0x39] as CFDictionary, 0) as? [IOHIDElement])?.count ?? 0
    let pageElements = (IOHIDDeviceCopyMatchingElements(device, ["UsagePage": 7] as CFDictionary, 0) as? [IOHIDElement])?.count ?? 0
    emit(["kind": "hidmgr", "device": String(id, radix: 16),
          "product": IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?",
          "transport": IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "?",
          "page7Elements": pageElements, "capsElements": capsElements])
}

// MARK: CGEventTap (listen-only, session)

let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
    | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14) // NSSystemDefined (media / caps toggles)
let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                            eventsOfInterest: mask, callback: { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        emit(["kind": "tap", "disabled": type.rawValue]); return Unmanaged.passUnretained(event)
    }
    // CGEventGetTimestamp is mach absolute time on Apple silicon/macOS 27 (verified by comparison in output).
    emit(["kind": "tap", "type": type.rawValue,
          "keycode": event.getIntegerValueField(.keyboardEventKeycode),
          "flags": String(event.flags.rawValue, radix: 16),
          "autorepeat": event.getIntegerValueField(.keyboardEventAutorepeat),
          "srcState": event.getIntegerValueField(.eventSourceStateID),
          "t": event.timestamp]) // CGEventTimestamp is already nanoseconds (checked against recv)
    return Unmanaged.passUnretained(event)
}, userInfo: nil)
if let tap {
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    emit(["kind": "tap", "created": true])
} else {
    emit(["kind": "tap", "created": false])
}

emit(["kind": "lockState", "alphaShift": CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)])
emit(["kind": "ready", "seconds": seconds, "sender": senderFilter.map { String($0, radix: 16) } ?? "any"])
let timer = DispatchSource.makeTimerSource(queue: .main)
var lastSecure = IsSecureEventInputEnabled()
timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
timer.setEventHandler {
    let secure = IsSecureEventInputEnabled()
    if secure != lastSecure { emit(["kind": "secureInput", "enabled": secure]); lastSecure = secure }
}
timer.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    emit(["kind": "lockState", "alphaShift": CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)])
    emit(["kind": "done"])
    _ = eventClient
    exit(0)
}
CFRunLoopRun()
