import ArgumentParser
import Foundation
import KeyPathAppKit

extension KeyPathTool {
    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check system status and health"
        )

        @Flag(help: "Output as JSON")
        var json: Bool = false

        mutating func run() async throws {
            let facade = await MainActor.run { CLIFacade() }
            let status = await facade.runStatus()

            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(status)
                print(String(data: data, encoding: .utf8) ?? "")
            } else {
                printHumanReadable(status)
            }

            if !status.isOperational {
                throw ExitCode.failure
            }
        }

        private func printHumanReadable(_ status: CLIStatusResult) {
            print("=== System Status ===")
            print("System Ready: \(status.isOperational ? "✅ Yes" : "❌ No")")

            print("\n--- Helper ---")
            print("Installed: \(status.helperInstalled ? "✅" : "❌")")
            print("Working: \(status.helperWorking ? "✅" : "❌")")
            if let version = status.helperVersion {
                print("Version: \(version)")
            }

            print("\n--- Permissions ---")
            print("KeyPath:")
            print("  Accessibility: \(status.keyPathAccessibility ? "✅" : "❌")")
            print("  Input Monitoring: \(status.keyPathInputMonitoring ? "✅" : "❌")")
            print("Kanata:")
            print("  Accessibility: \(status.kanataAccessibility ? "✅" : "❌")")
            print("  Input Monitoring: \(status.kanataInputMonitoring ? "✅" : "❌")")

            print("\n--- Components ---")
            print("Kanata Binary: \(status.kanataBinaryInstalled ? "✅ Installed" : "❌ Missing")")
            print("Karabiner Driver: \(status.karabinerDriverInstalled ? "✅ Installed" : "❌ Missing")")
            print("VHID Device: \(status.vhidDeviceHealthy ? "✅ Healthy" : "❌ Unhealthy")")

            print("\n--- Services ---")
            print("Kanata Running: \(status.kanataRunning ? "✅" : "❌")")
            print("Karabiner Daemon: \(status.karabinerDaemonRunning ? "✅" : "❌")")
            print("VHID Healthy: \(status.vhidHealthy ? "✅" : "❌")")

            if status.hasConflicts {
                print("\n⚠️  Conflicts detected")
            }

            print("\n=== Summary ===")
            if status.isOperational {
                print("✅ System is ready and operational")
            } else {
                print("❌ System has blocking issue(s)")
                print("   Run 'keypath repair' or 'keypath install' to fix")
            }
        }
    }
}
