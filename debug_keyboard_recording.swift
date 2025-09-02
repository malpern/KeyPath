#!/usr/bin/env swift

// Simple standalone debug script to test keyboard recording
// Run with: swift debug_keyboard_recording.swift

import Foundation
import ApplicationServices

// Minimal mock to test the logic without full KeyPath dependencies
@MainActor
class PermissionOracleMock {
    static let shared = PermissionOracleMock()
    
    struct PermissionStatus {
        let isReady: Bool
    }
    
    struct KeyPathPermissions {
        let accessibility: PermissionStatus
        let inputMonitoring: PermissionStatus
    }
    
    struct Snapshot {
        let keyPath: KeyPathPermissions
    }
    
    func currentSnapshot() async -> Snapshot {
        // Check actual system permissions
        let axGranted = AXIsProcessTrusted()
        
        // For Input Monitoring, we'll use IOHIDCheckAccess 
        let imGranted: Bool
        if #available(macOS 10.15, *) {
            imGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        } else {
            imGranted = true // Assume granted on older versions
        }
        
        print("🧪 [Debug] System permission check:")
        print("🧪 [Debug] - Accessibility: \(axGranted)")
        print("🧪 [Debug] - Input Monitoring: \(imGranted)")
        
        return Snapshot(
            keyPath: KeyPathPermissions(
                accessibility: PermissionStatus(isReady: axGranted),
                inputMonitoring: PermissionStatus(isReady: imGranted)
            )
        )
    }
}

// Test the permission check logic that KeyboardCapture uses
@MainActor
func testPermissionCheck() async {
    print("🧪 [Debug] Testing permission check logic...")
    
    let snapshot = await PermissionOracleMock.shared.currentSnapshot()
    
    // This is the logic from KeyboardCapture.checkAccessibilityPermissionsSilently()
    let permissionCheckResult = snapshot.keyPath.accessibility.isReady && snapshot.keyPath.inputMonitoring.isReady
    
    print("🧪 [Debug] Combined permission check result: \(permissionCheckResult)")
    
    if permissionCheckResult {
        print("✅ [Debug] Permission check PASSED - recording should work")
        await testEventTapCreation()
    } else {
        print("❌ [Debug] Permission check FAILED - recording will not work")
        print("🧪 [Debug] Missing permissions:")
        if !snapshot.keyPath.accessibility.isReady {
            print("  - Accessibility permission required")
        }
        if !snapshot.keyPath.inputMonitoring.isReady {
            print("  - Input Monitoring permission required")
        }
    }
}

@MainActor
func testEventTapCreation() async {
    print("🧪 [Debug] Testing CGEvent tap creation...")
    
    // Try to create an event tap like KeyboardCapture does
    let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
        callback: { proxy, type, event, refcon in
            print("🧪 [Debug] Event tap received event: \(type)")
            return Unmanaged.passUnretained(event)
        },
        userInfo: nil
    )
    
    if let eventTap = eventTap {
        print("✅ [Debug] CGEvent tap created successfully")
        
        // Test if we can create a run loop source
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if runLoopSource != nil {
            print("✅ [Debug] RunLoop source created successfully")
            print("🧪 [Debug] Event tap setup would succeed")
        } else {
            print("❌ [Debug] Failed to create RunLoop source")
        }
        
        // Clean up
        CFMachPortInvalidate(eventTap)
    } else {
        print("❌ [Debug] Failed to create CGEvent tap")
        print("🧪 [Debug] This is why keyboard recording fails")
    }
}

@MainActor
func main() async {
    print("🧪 [Debug] Keyboard Recording Debug Tool")
    print("🧪 [Debug] ==================================")
    
    await testPermissionCheck()
    
    print("🧪 [Debug] Debug completed")
}

await main()