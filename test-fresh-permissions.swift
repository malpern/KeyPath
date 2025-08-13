#!/usr/bin/env swift

import Foundation

// Test what permission detection returns for fresh app
print("🧪 Testing Fresh App Permission Detection")
print("========================================")

// This simulates what PermissionService.shared.checkSystemPermissions() should return
print("Expected for fresh app in /Applications:")
print("  - KeyPath Input Monitoring: FALSE")
print("  - KeyPath Accessibility: FALSE") 
print("  - Kanata Input Monitoring: FALSE")
print("  - Kanata Accessibility: FALSE")
print("")

// The fresh app should show these as missing permissions
print("If wizard shows all green, then permission detection is broken.")
print("A fresh app should NEVER have any permissions granted.")
print("")
print("Check: System Preferences > Privacy & Security > Input Monitoring")
print("Check: System Preferences > Privacy & Security > Accessibility")
print("Should KeyPath (/Applications/KeyPath.app) be listed? NO for fresh install")