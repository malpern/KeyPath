#!/usr/bin/env swift

import Foundation
import ServiceManagement

let helperIdentifier = "com.keypath.KeyPath.helper"

print("🔍 Checking SMAppService status for: \(helperIdentifier)")

if #available(macOS 13.0, *) {
    let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")

    print("📋 Service properties:")
    print("  - Identifier: \(helperIdentifier)")
    print("  - Plist name: \(helperIdentifier).plist")

    let status = service.status
    print("  - Status: \(status) (\(status.rawValue))")

    switch status {
    case .notRegistered:
        print("    → Service is not registered")
    case .enabled:
        print("    → Service is registered and enabled")
    case .requiresApproval:
        print("    → Service requires user approval")
    case .notFound:
        print("    → Service plist not found")
    @unknown default:
        print("    → Unknown status")
    }

    // Try to check if we can get more info about why it's not working
    print("\n🔍 Attempting to get service info...")

    do {
        try service.register()
        print("✅ Registration succeeded (or was already registered)")
    } catch {
        print("❌ Registration failed: \(error)")
        print("   Error type: \(type(of: error))")

        if let nsError = error as NSError? {
            print("   NSError domain: \(nsError.domain)")
            print("   NSError code: \(nsError.code)")
        }
    }

    // Check the status again
    let newStatus = service.status
    print("\n📊 Status after registration attempt: \(newStatus) (\(newStatus.rawValue))")

} else {
    print("❌ SMAppService not available on this macOS version")
}
