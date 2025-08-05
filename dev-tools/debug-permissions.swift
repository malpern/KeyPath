#!/usr/bin/env swift

import ApplicationServices
import Foundation
import IOKit.hid

print("=== Detailed Permission Debug ===")
print("Current executable path: \(CommandLine.arguments[0])")
print("Process info: \(ProcessInfo.processInfo.processName)")

// Test Input Monitoring permission
if #available(macOS 10.15, *) {
    let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    let inputMonitoring = accessType == kIOHIDAccessTypeGranted
    print("Input Monitoring: \(inputMonitoring) (raw: \(accessType.rawValue))")
} else {
    print("Input Monitoring: macOS < 10.15")
}

// Test Accessibility permission
let accessibility = AXIsProcessTrusted()
print("Accessibility (AXIsProcessTrusted): \(accessibility)")

// Test event tap creation (the actual capability we need)
let eventMask = (1 << CGEventType.keyDown.rawValue)
let testTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(eventMask),
    callback: { _, _, event, _ in Unmanaged.passRetained(event) },
    userInfo: nil
)

let canCreateTap = testTap != nil
if let tap = testTap {
    CFMachPortInvalidate(tap)
}

print("Event tap creation test: \(canCreateTap)")
print("========================")
