import ArgumentParser
import AppKit
import Foundation
import KeyPathAppKit
import KeyPathCLISupport

struct SystemUninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove KeyPath services and components"
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .customLong("delete-config"), help: "Also delete user configuration files")
    var deleteConfig: Bool = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        if deleteConfig {
            CLIOutput.progress("Starting uninstall (configuration will be deleted)...", context: ctx)
        } else {
            CLIOutput.progress("Starting uninstall (configuration will be preserved)...", context: ctx)
        }

        guard await terminateRunningKeyPathApplication(context: ctx) else {
            throw ValidationError("The running KeyPath application could not be closed.")
        }

        let facade = SystemFacade()
        let shouldDeleteConfig = deleteConfig
        let timeoutSeconds = globals.timeout
        let report: CLIInstallerReport
        do {
            report = try await withThrowingTimeout(seconds: timeoutSeconds) {
                await facade.runUninstall(deleteConfig: shouldDeleteConfig)
            }
        } catch is TimeoutError {
            CLIOutput.progress("Uninstall timed out after \(timeoutSeconds)s", context: ctx)
            throw ExitCode.failure
        }

        CLIOutput.write(report, context: ctx) {
            formatInstallerReport(report, title: "Uninstall")
        }

        if !report.success {
            throw ExitCode.failure
        }
    }

    @MainActor
    private func terminateRunningKeyPathApplication(context: OutputContext) async -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.keypath.KeyPath"
        ).filter { $0.processIdentifier != currentPID && !$0.isTerminated }

        guard !applications.isEmpty else { return true }

        CLIOutput.progress("Closing the running KeyPath application...", context: context)
        for application in applications {
            _ = application.terminate()
        }

        for _ in 0..<30 where applications.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(100))
        }

        for application in applications where !application.isTerminated {
            _ = application.forceTerminate()
        }

        for _ in 0..<20 where applications.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(100))
        }

        return applications.allSatisfy(\.isTerminated)
    }
}
