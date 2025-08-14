#!/usr/bin/env swift

import Foundation

// Test script to trace the Fix button flow for kanataService missing issue
// This simulates what happens when the user clicks "Fix" on Kanata Service Configuration

print("🔍 Testing Fix Button Flow for Kanata Service Configuration")
print(String(repeating: "=", count: 60))

class MockLaunchDaemonInstaller {
    static let kanataServiceID = "com.keypath.kanata"
    static let launchDaemonsPath = "/Library/LaunchDaemons"
    
    func getServiceStatus() -> (kanataServiceLoaded: Bool, kanataServiceHealthy: Bool) {
        let plistExists = FileManager.default.fileExists(atPath: "\(Self.launchDaemonsPath)/\(Self.kanataServiceID).plist")
        print("📁 Kanata plist exists: \(plistExists)")
        
        // For this test, assume service exists but is unhealthy
        return (kanataServiceLoaded: plistExists, kanataServiceHealthy: false)
    }
    
    func createConfigureAndLoadAllServices() -> Bool {
        print("🔧 [LaunchDaemon] createConfigureAndLoadAllServices() called")
        print("   This method should show osascript password prompt...")
        print("   executeConsolidatedInstallation() should run with:")
        print("   do shell script \"[install commands]\" with administrator privileges")
        
        // Simulate osascript call
        print("🔐 OSASCRIPT PROMPT SHOULD APPEAR HERE:")
        print("   'KeyPath needs administrator access to install LaunchDaemon services...'")
        
        // For testing, return success
        return true
    }
}

class MockComponentDetector {
    func checkComponents() -> (missing: [String], installed: [String]) {
        let installer = MockLaunchDaemonInstaller()
        let status = installer.getServiceStatus()
        
        var missing: [String] = []
        var installed: [String] = []
        
        // This is the key logic from ComponentDetector.checkComponents()
        if status.kanataServiceLoaded && status.kanataServiceHealthy {
            installed.append("kanataService")
        } else {
            missing.append("kanataService")
            print("❌ kanataService marked as MISSING")
            print("   Reason: loaded=\(status.kanataServiceLoaded), healthy=\(status.kanataServiceHealthy)")
        }
        
        return (missing: missing, installed: installed)
    }
}

class MockWizardAutoFixer {
    let launchDaemonInstaller = MockLaunchDaemonInstaller()
    
    func installLaunchDaemonServices() async -> Bool {
        print("🔧 [AutoFixer] installLaunchDaemonServices() called")
        print("   About to call createConfigureAndLoadAllServices()...")
        
        let success = launchDaemonInstaller.createConfigureAndLoadAllServices()
        
        if success {
            print("✅ [AutoFixer] LaunchDaemon installation completed successfully")
        } else {
            print("❌ [AutoFixer] LaunchDaemon installation failed")
        }
        
        return success
    }
}

// Simulate the flow
print("1. User sees 'Failed to install system services' for Kanata Service Configuration")
print("2. User clicks 'Fix' button")
print()

let componentDetector = MockComponentDetector()
let result = componentDetector.checkComponents()

print("3. Component Detection Results:")
print("   Missing: \(result.missing)")
print("   Installed: \(result.installed)")
print()

if result.missing.contains("kanataService") {
    print("4. kanataService missing -> maps to .installLaunchDaemonServices auto-fix action")
    print("5. WizardAutoFixer.installLaunchDaemonServices() will be called")
    print()
    
    let autoFixer = MockWizardAutoFixer()
    Task {
        let success = await autoFixer.installLaunchDaemonServices()
        print()
        print("6. Final Result: \(success ? "SUCCESS" : "FAILED")")
        print()
        print("🤔 If you don't see the osascript password prompt in the real app,")
        print("   the issue might be:")
        print("   A) Different code path is being taken")
        print("   B) osascript is being suppressed/blocked somehow")
        print("   C) The Fix button isn't actually calling this method")
        print("   D) There's an early return before osascript is reached")
    }
}