#!/usr/bin/env swift

import Foundation

print("🔮 Testing Oracle Permission Detection Fix")
print("==========================================")

// Test if we can access the bundled kanata path
let bundledPath = Bundle.main.bundlePath + "/Contents/Library/KeyPath/kanata"
print("📁 Bundled kanata path: \(bundledPath)")

let fileExists = FileManager.default.fileExists(atPath: bundledPath)
print("📁 File exists: \(fileExists)")

// Test IOHIDCheckAccess from GUI context
import IOKit.hid

let accessResult = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
let hasInputMonitoring = accessResult == kIOHIDAccessTypeGranted
print("🔐 Input Monitoring from GUI context: \(hasInputMonitoring ? "✅ granted" : "❌ denied")")

// Test Accessibility
import ApplicationServices

let hasAccessibility = AXIsProcessTrusted()
print("♿ Accessibility from GUI context: \(hasAccessibility ? "✅ granted" : "❌ denied")")

print("\n🎯 This shows what Oracle will now detect (GUI context)")
print("   Previous issue: kanata TCP reported false negatives")
print("   New approach: reliable GUI-based permission detection")
