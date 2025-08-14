#!/usr/bin/env swift

import Foundation

// Updated test script using the new health check logic (PID present = healthy for keep-alive services)

class LaunchDaemonInstaller {
    private static let kanataServiceID = "com.keypath.kanata"
    private static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"
    private static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"

    func getServiceStatus() -> LaunchDaemonStatus {
        print("🔍 [DEBUG] Checking service status with NEW logic...")

        let kanataLoaded = isServiceLoaded(serviceID: Self.kanataServiceID)
        let vhidDaemonLoaded = isServiceLoaded(serviceID: Self.vhidDaemonServiceID)
        let vhidManagerLoaded = isServiceLoaded(serviceID: Self.vhidManagerServiceID)

        let kanataHealthy = isServiceHealthy(serviceID: Self.kanataServiceID)
        let vhidDaemonHealthy = isServiceHealthy(serviceID: Self.vhidDaemonServiceID)
        let vhidManagerHealthy = isServiceHealthy(serviceID: Self.vhidManagerServiceID)

        print("   Kanata: loaded=\(kanataLoaded) healthy=\(kanataHealthy)")
        print("   VHIDDaemon: loaded=\(vhidDaemonLoaded) healthy=\(vhidDaemonHealthy)")
        print("   VHIDManager: loaded=\(vhidManagerLoaded) healthy=\(vhidManagerHealthy)")

        return LaunchDaemonStatus(
            kanataServiceLoaded: kanataLoaded,
            vhidDaemonServiceLoaded: vhidDaemonLoaded,
            vhidManagerServiceLoaded: vhidManagerLoaded,
            kanataServiceHealthy: kanataHealthy,
            vhidDaemonServiceHealthy: vhidDaemonHealthy,
            vhidManagerServiceHealthy: vhidManagerHealthy
        )
    }

    private func isServiceLoaded(serviceID: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", serviceID]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let isLoaded = task.terminationStatus == 0
            print("     isServiceLoaded(\(serviceID)): \(isLoaded)")
            return isLoaded
        } catch {
            print("     ERROR isServiceLoaded(\(serviceID)): \(error)")
            return false
        }
    }

    private func isServiceHealthy(serviceID: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", serviceID]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            guard task.terminationStatus == 0 else {
                print("     isServiceHealthy(\(serviceID)): false (not loaded)")
                return false
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let lastExitCode = output.firstMatchInt(pattern: #""LastExitStatus"\s*=\s*(-?\d+);"#) ?? 0
            let pid = output.firstMatchInt(pattern: #""PID"\s*=\s*([0-9]+);"#)
            let hasPID = (pid != nil)

            // NEW LOGIC: Improved KeepAlive semantics:
            // - Manager is a one-shot (no KeepAlive required to be running)
            // - Others (Kanata, VHID Daemon) should be running (PID present)
            // - For keep-alive services, PID present is more important than lastExitCode == 0
            let isOneShot = (serviceID == Self.vhidManagerServiceID)
            let healthy: Bool = isOneShot
                ? (lastExitCode == 0)                               // one-shot OK without PID if exit was clean
                : hasPID                                            // keep-alive services healthy if running (PID present)

            print("     isServiceHealthy(\(serviceID)): \(healthy) (pid=\(pid?.description ?? "nil") lastExit=\(lastExitCode) oneShot=\(isOneShot)) [NEW LOGIC]")
            return healthy
        } catch {
            print("     ERROR isServiceHealthy(\(serviceID)): \(error)")
            return false
        }
    }
}

struct LaunchDaemonStatus {
    let kanataServiceLoaded: Bool
    let vhidDaemonServiceLoaded: Bool
    let vhidManagerServiceLoaded: Bool
    let kanataServiceHealthy: Bool
    let vhidDaemonServiceHealthy: Bool
    let vhidManagerServiceHealthy: Bool

    var allServicesHealthy: Bool {
        kanataServiceHealthy && vhidDaemonServiceHealthy && vhidManagerServiceHealthy
    }
}

extension String {
    func firstMatchInt(pattern: String) -> Int? {
        do {
            let rx = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(startIndex..., in: self)
            guard let m = rx.firstMatch(in: self, range: nsRange), m.numberOfRanges >= 2,
                  let range = Range(m.range(at: 1), in: self) else {
                return nil
            }
            return Int(self[range])
        } catch {
            return nil
        }
    }
}

// Main execution
print("🔍 [DEBUG] ===== Testing NEW LaunchDaemon Health Check Logic =====")

let installer = LaunchDaemonInstaller()

print("\n1. Service status check with NEW logic (PID present = healthy):")
let status = installer.getServiceStatus()

if status.allServicesHealthy {
    print("✅ ALL SERVICES HEALTHY! This means the 'Fix' button should work now.")
    print("   The user would see services as GREEN instead of RED.")
} else {
    print("⚠️ Some services still considered unhealthy with new logic")
    print("   kanataServiceHealthy: \(status.kanataServiceHealthy)")
    print("   vhidDaemonServiceHealthy: \(status.vhidDaemonServiceHealthy)")
    print("   vhidManagerServiceHealthy: \(status.vhidManagerServiceHealthy)")
}

print("\n2. Analysis:")
print("   - NEW logic: PID present = healthy (ignores exit codes for keep-alive services)")
print("   - OLD logic: PID present AND exit code 0 = healthy (too strict)")
print("   - This change should fix the 'Fix' button appearing to fail")
