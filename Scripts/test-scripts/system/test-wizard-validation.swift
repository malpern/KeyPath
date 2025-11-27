#!/usr/bin/env swift

import Foundation
import KeyPathAppKit

/// Validates wizard detection using the InstallerEngine snapshot and reports
/// what the wizard should display for LaunchDaemon services.
@main
struct TestWizardValidation {
    static func main() async {
        print("🧪 Testing Wizard Validation Logic (InstallerEngine)")
        print(String(repeating: "=", count: 38))

        let engine = InstallerEngine()
        let context = await engine.inspectSystem()
        let services = context.services.launchDaemons

        print("\n📋 LaunchDaemon snapshot:")
        print("  Kanata loaded/healthy:     \(services.kanataServiceLoaded)/\(services.kanataServiceHealthy)")
        print("  VHID Daemon loaded/healthy:\(services.vhidDaemonServiceLoaded)/\(services.vhidDaemonServiceHealthy)")
        print("  VHID Manager loaded/healthy:\(services.vhidManagerServiceLoaded)/\(services.vhidManagerServiceHealthy)")

        let allHealthy = services.kanataServiceHealthy
            && services.vhidDaemonServiceHealthy
            && services.vhidManagerServiceHealthy
        let loadedButUnhealthy = (services.kanataServiceLoaded && !services.kanataServiceHealthy)
            || (services.vhidDaemonServiceLoaded && !services.vhidDaemonServiceHealthy)
            || (services.vhidManagerServiceLoaded && !services.vhidManagerServiceHealthy)

        print("\n🎯 Wizard classification:")
        if allHealthy {
            print("  🟢 INSTALLED (all services healthy)")
        } else if loadedButUnhealthy {
            print("  🟡 Services failing → auto-fix: restartUnhealthyServices")
        } else {
            print("  🔴 Services missing → auto-fix: installLaunchDaemonServices")
        }

        print("\n✅ Snapshot timestamp: \(context.timestamp)")
    }
}
