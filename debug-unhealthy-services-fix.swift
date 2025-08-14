#!/usr/bin/env swift

import Foundation

// Test script to debug the exact LaunchDaemon services auto-fix flow
// This will trace the complete execution path when "Fix" button is clicked

class LaunchDaemonInstaller {
    private static let kanataServiceID = "com.keypath.kanata"
    private static let vhidDaemonServiceID = "com.keypath.karabiner-vhiddaemon"
    private static let vhidManagerServiceID = "com.keypath.karabiner-vhidmanager"

    func getServiceStatus() -> LaunchDaemonStatus {
        print("🔍 [DEBUG] Checking service status...")

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

            let isOneShot = (serviceID == Self.vhidManagerServiceID)
            let healthy: Bool = isOneShot
                ? (lastExitCode == 0)
                : (hasPID && lastExitCode == 0)

            print("     isServiceHealthy(\(serviceID)): \(healthy) (pid=\(pid?.description ?? "nil") lastExit=\(lastExitCode) oneShot=\(isOneShot))")
            return healthy
        } catch {
            print("     ERROR isServiceHealthy(\(serviceID)): \(error)")
            return false
        }
    }

    func restartUnhealthyServices() async -> Bool {
        print("🔧 [DEBUG] Starting restartUnhealthyServices()...")

        let initialStatus = getServiceStatus()
        var toRestart: [String] = []

        if initialStatus.kanataServiceLoaded && !initialStatus.kanataServiceHealthy {
            toRestart.append(Self.kanataServiceID)
        }
        if initialStatus.vhidDaemonServiceLoaded && !initialStatus.vhidDaemonServiceHealthy {
            toRestart.append(Self.vhidDaemonServiceID)
        }
        if initialStatus.vhidManagerServiceLoaded && !initialStatus.vhidManagerServiceHealthy {
            toRestart.append(Self.vhidManagerServiceID)
        }

        guard !toRestart.isEmpty else {
            print("✅ [DEBUG] No unhealthy services found to restart")
            return true
        }

        print("🔧 [DEBUG] Services to restart: \(toRestart)")

        // Step 1: Execute the restart command
        let restartOk = restartServicesWithAdmin(toRestart)
        if !restartOk {
            print("❌ [DEBUG] Failed to execute restart commands")
            return false
        }

        print("✅ [DEBUG] Restart commands executed successfully")

        // Step 2: Wait for services to start up
        print("⏳ [DEBUG] Waiting 3 seconds for services to start up...")
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Step 3: Re-check service health
        let finalStatus = getServiceStatus()
        var stillUnhealthy: [String] = []

        if toRestart.contains(Self.kanataServiceID) && !finalStatus.kanataServiceHealthy {
            stillUnhealthy.append(Self.kanataServiceID)
        }
        if toRestart.contains(Self.vhidDaemonServiceID) && !finalStatus.vhidDaemonServiceHealthy {
            stillUnhealthy.append(Self.vhidDaemonServiceID)
        }
        if toRestart.contains(Self.vhidManagerServiceID) && !finalStatus.vhidManagerServiceHealthy {
            stillUnhealthy.append(Self.vhidManagerServiceID)
        }

        if stillUnhealthy.isEmpty {
            print("✅ [DEBUG] All restarted services are now healthy")
            return true
        } else {
            print("⚠️ [DEBUG] Some services are still unhealthy after restart: \(stillUnhealthy)")
            return false
        }
    }

    private func restartServicesWithAdmin(_ serviceIDs: [String]) -> Bool {
        guard !serviceIDs.isEmpty else { return true }

        print("🔧 [DEBUG] Executing restart with admin privileges...")

        let cmds = serviceIDs.map { "launchctl kickstart -k system/\($0)" }.joined(separator: " && ")
        let script = """
        do shell script "\(cmds)" with administrator privileges with prompt "KeyPath needs to restart failing system services."
        """

        print("   Command: \(cmds)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let success = task.terminationStatus == 0
            print("   Exit status: \(task.terminationStatus)")
            if !output.isEmpty {
                print("   Output: \(output)")
            }

            return success
        } catch {
            print("   ERROR: \(error)")
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
print("🔍 [DEBUG] ===== Testing LaunchDaemon Services Auto-Fix Flow =====")

let installer = LaunchDaemonInstaller()

print("\n1. Initial service status check:")
let initialStatus = installer.getServiceStatus()

if initialStatus.allServicesHealthy {
    print("✅ All services are healthy - no fix needed")
} else {
    print("⚠️ Some services are unhealthy - testing fix...")

    print("\n2. Executing restartUnhealthyServices():")
    Task {
        let result = await installer.restartUnhealthyServices()
        print("\n3. Final result: \(result ? "SUCCESS" : "FAILED")")

        if !result {
            print("\n4. This is the exact failure the user sees!")
            print("   Error message would be: 'Failed to restart failed system services'")
        }

        exit(result ? 0 : 1)
    }

    RunLoop.main.run()
}
