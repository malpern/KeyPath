#!/usr/bin/env swift

import Foundation
import IOKit.hid
import ApplicationServices

// Test the same permission checks our app uses
print("=== Permission Test ===")

var inputMonitoring = false

// Test Input Monitoring permission
if #available(macOS 10.15, *) {
    let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    inputMonitoring = accessType == kIOHIDAccessTypeGranted
    print("Input Monitoring: \(inputMonitoring) (raw: \(accessType.rawValue))")
} else {
    print("Input Monitoring: macOS < 10.15")
}

// Test Accessibility permission
let accessibility = AXIsProcessTrusted()
print("Accessibility: \(accessibility)")

// Combined result
let combined = inputMonitoring && accessibility
print("Combined (both required): \(combined)")

print("========================")