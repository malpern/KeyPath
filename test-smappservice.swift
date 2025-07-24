#!/usr/bin/env swift

import Foundation
import ServiceManagement

// Test SMAppService registration
let helperIdentifier = "com.keypath.helper"

@available(macOS 13.0, *)
func testSMAppService() {
    print("Testing SMAppService registration...")
    
    let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
    print("Created SMAppService with plist: \(helperIdentifier).plist")
    
    // Check current status
    print("Current service status: \(service.status)")
    
    do {
        try service.register()
        print("✅ Successfully registered privileged helper via SMAppService")
        
        // Check status after registration
        print("Service status after registration: \(service.status)")
        
    } catch {
        print("❌ SMAppService registration failed: \(error)")
        print("❌ Error details: \(error.localizedDescription)")
    }
}

if #available(macOS 13.0, *) {
    testSMAppService()
} else {
    print("SMAppService requires macOS 13.0 or later")
}