#!/usr/bin/env swift

import ApplicationServices
import Foundation

// Test the actual permission APIs that are giving false positives
print("🧪 Testing Permission APIs for Fresh App")
print("=========================================")

print("App path: \(Bundle.main.bundlePath)")
print("Expected for FRESH app: All permissions should be FALSE")
print("")

// Test IOHIDCheckAccess (Input Monitoring)
let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
let inputMonitoringGranted = accessType == kIOHIDAccessTypeGranted
print("🔍 IOHIDCheckAccess (Input Monitoring): \(inputMonitoringGranted)")
print("   Raw access type: \(accessType)")

// Test AXIsProcessTrusted (Accessibility)
let accessibilityGranted = AXIsProcessTrusted()
print("🔍 AXIsProcessTrusted (Accessibility): \(accessibilityGranted)")

print("")
print("🚨 PROBLEM: If either returns true for a fresh app, that's the bug!")
print("Fresh apps should have NO permissions until user grants them.")
print("")
print("Check System Preferences > Privacy & Security:")
print("- Input Monitoring: Should KeyPath be listed? NO")
print("- Accessibility: Should KeyPath be listed? NO")
