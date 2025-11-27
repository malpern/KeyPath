#!/usr/bin/env swift

import Foundation
import KeyPathAppKit

/// Diagnostic script that runs the InstallerEngine detection pass
/// and prints the wizard-facing system snapshot. Mirrors production
/// detection (no direct launchctl/TCC access).
@main
struct TestDetectionDebug {
    static func main() async {
        print("🐛 Debugging InstallerEngine Detection Logic")
        print(String(repeating: "=", count: 40))

        let engine = InstallerEngine()
        let context = await engine.inspectSystem()

        // Permissions
        print("\n🔐 Permissions:")
        print("  Input Monitoring granted: \(context.permissions.inputMonitoring.granted)")
        print("  Accessibility granted:    \(context.permissions.accessibility.granted)")
        print("  Full Disk Access granted: \(context.permissions.fullDiskAccess.granted)")

        // Services
        print("\n🛠️  LaunchDaemon Services:")
        print("  Kanata running/responding: \(context.services.kanata.isRunning)/\(context.services.kanata.isResponding)")
        print("  VHID Daemon loaded/healthy: \(context.services.launchDaemons.vhidDaemonServiceLoaded)/\(context.services.launchDaemons.vhidDaemonServiceHealthy)")
        print("  VHID Manager loaded/healthy: \(context.services.launchDaemons.vhidManagerServiceLoaded)/\(context.services.launchDaemons.vhidManagerServiceHealthy)")

        // Components
        print("\n📦 Components:")
        print("  Kanata binary installed: \(context.components.kanataBinaryInstalled)")
        print("  Driver installed:        \(context.components.driverInstalled)")
        print("  Helper registered:       \(context.helper.isReady)")

        print("\n✅ Snapshot timestamp: \(context.timestamp)")
    }
}
