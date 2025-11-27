#!/usr/bin/env swift

import Foundation
import KeyPathAppKit

/// Service detection debug script that mirrors the wizard by using InstallerEngine.
/// Prints service health, conflicts, and a suggested auto-fix action.
@main
struct DebugServiceDetection {
    static func main() async {
        print("🔍 InstallerEngine service detection")
        print(String(repeating: "=", count: 40))

        let engine = InstallerEngine()
        let context = await engine.inspectSystem()

        // Service health
        let services = context.services.launchDaemons
        print("\n🛠️  LaunchDaemon services:")
        print("  Kanata loaded/healthy:      \(services.kanataServiceLoaded)/\(services.kanataServiceHealthy)")
        print("  VHID Daemon loaded/healthy: \(services.vhidDaemonServiceLoaded)/\(services.vhidDaemonServiceHealthy)")
        print("  VHID Manager loaded/healthy:\(services.vhidManagerServiceLoaded)/\(services.vhidManagerServiceHealthy)")

        // Conflicts
        if !context.conflicts.processConflicts.isEmpty {
            print("\n⚠️  Conflicts:")
            context.conflicts.processConflicts.forEach { print("  - \($0.description)") }
        }

        // Suggested action
        let allHealthy = services.kanataServiceHealthy
            && services.vhidDaemonServiceHealthy
            && services.vhidManagerServiceHealthy
        let loadedButUnhealthy = (services.kanataServiceLoaded && !services.kanataServiceHealthy)
            || (services.vhidDaemonServiceLoaded && !services.vhidDaemonServiceHealthy)
            || (services.vhidManagerServiceLoaded && !services.vhidManagerServiceHealthy)

        print("\n🎯 Suggested wizard state:")
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
