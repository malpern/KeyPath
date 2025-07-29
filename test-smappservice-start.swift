#!/usr/bin/env swift

import Foundation
import ServiceManagement

let helperIdentifier = "com.keypath.KeyPath.helper"

print("🔧 Testing SMAppService daemon start for: \(helperIdentifier)")

if #available(macOS 13.0, *) {
    let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
    
    print("📋 Current status: \(service.status)")
    
    // First, try to unregister and re-register to force a fresh start
    do {
        print("🗑️ Attempting to unregister first...")
        try service.unregister()
        print("✅ Unregister successful")
        
        print("⏳ Waiting 2 seconds...")
        sleep(2)
        
        print("🚀 Re-registering...")
        try service.register()
        print("✅ Re-registration successful!")
        
        print("📊 Final status: \(service.status)")
        
    } catch {
        print("❌ Operation failed: \(error)")
        
        if let nsError = error as NSError? {
            print("   Domain: \(nsError.domain)")
            print("   Code: \(nsError.code)")
            print("   Description: \(nsError.localizedDescription)")
        }
    }
    
} else {
    print("❌ SMAppService not available on this macOS version")
}