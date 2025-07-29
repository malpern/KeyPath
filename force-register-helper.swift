#!/usr/bin/env swift

import Foundation
import ServiceManagement

let helperIdentifier = "com.keypath.KeyPath.helper"

print("🔧 Force registering SMAppService for: \(helperIdentifier)")

if #available(macOS 13.0, *) {
    let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
    
    print("📋 Current status: \(service.status)")
    
    do {
        print("🚀 Attempting to register...")
        try service.register()
        print("✅ Registration successful!")
        
        // Check status again
        let newStatus = service.status
        print("📊 New status: \(newStatus)")
        
        // Give it a moment and check launchctl
        print("⏳ Waiting 3 seconds for service to start...")
        sleep(3)
        
    } catch {
        print("❌ Registration failed: \(error)")
        
        if let nsError = error as NSError? {
            print("   Domain: \(nsError.domain)")
            print("   Code: \(nsError.code)")
            print("   Description: \(nsError.localizedDescription)")
        }
    }
    
} else {
    print("❌ SMAppService not available on this macOS version")
}