import ArgumentParser
import Foundation
import KeyPathAppKit

struct ServiceStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check system status and health"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(help: "Timeout in seconds (default: 30)")
    var timeout: Int = 30

    mutating func run() async throws {
        let ctx = globals.outputContext
        let facade = CLIFacade()
        let status: CLIStatusResult
        do {
            status = try await withThrowingTimeout(seconds: timeout) {
                await facade.runStatus()
            }
        } catch is TimeoutError {
            let error = CLIError(
                code: .serviceUnreachable,
                message: "Status check timed out after \(timeout)s",
                hint: "SMAppService IPC may be slow. Try again or increase --timeout",
                details: nil,
                docsUrl: nil
            )
            CLIOutput.writeError(error, context: ctx)
            throw error.code.exitCode
        }

        CLIOutput.write(status, context: ctx) {
            formatHumanReadable(status, noColor: ctx.noColor)
        }

        if ctx.isInteractive, !ctx.shouldOutputJSON {
            if let newVersion = await UpdateChecker.checkOnce() {
                let nudge = ANSIColor.yellow(
                    "Update available: v\(newVersion) — brew upgrade keypath",
                    noColor: ctx.noColor
                )
                printErr("")
                printErr(nudge)
            }
        }

        if !status.isOperational {
            throw ExitCode.failure
        }
    }
}

private func formatHumanReadable(_ status: CLIStatusResult, noColor: Bool) -> String {
    let ok = ANSIColor.green("✓", noColor: noColor)
    let fail = ANSIColor.red("✗", noColor: noColor)

    func check(_ value: Bool) -> String { value ? ok : fail }

    var lines: [String] = []
    lines.append(ANSIColor.bold("=== System Status ===", noColor: noColor))
    lines.append("System Ready: \(check(status.isOperational))")
    lines.append("")
    lines.append("--- Helper ---")
    lines.append("Installed: \(check(status.helperInstalled))")
    lines.append("Working: \(check(status.helperWorking))")
    if let version = status.helperVersion {
        lines.append("Version: \(version)")
    }
    lines.append("")
    lines.append("--- Permissions ---")
    lines.append("KeyPath:")
    lines.append("  Accessibility: \(check(status.keyPathAccessibility))")
    lines.append("  Input Monitoring: \(check(status.keyPathInputMonitoring))")
    lines.append("Kanata:")
    lines.append("  Accessibility: \(check(status.kanataAccessibility))")
    lines.append("  Input Monitoring: \(check(status.kanataInputMonitoring))")
    lines.append("")
    lines.append("--- Components ---")
    lines.append("Kanata Binary: \(check(status.kanataBinaryInstalled))")
    lines.append("Karabiner Driver: \(check(status.karabinerDriverInstalled))")
    lines.append("VHID Device: \(check(status.vhidDeviceHealthy))")
    lines.append("")
    lines.append("--- Services ---")
    lines.append("Kanata Running: \(check(status.kanataRunning))")
    lines.append("Karabiner Daemon: \(check(status.karabinerDaemonRunning))")
    lines.append("VHID Healthy: \(check(status.vhidHealthy))")

    if status.hasConflicts {
        lines.append("")
        lines.append(ANSIColor.yellow("Conflicts detected", noColor: noColor))
    }

    lines.append("")
    lines.append(ANSIColor.bold("=== Summary ===", noColor: noColor))
    if status.isOperational {
        lines.append(ANSIColor.green("System is ready and operational", noColor: noColor))
    } else {
        lines.append(ANSIColor.red("System has blocking issue(s)", noColor: noColor))
        lines.append("   Open KeyPath.app and use the Installation Wizard to fix")
    }

    return lines.joined(separator: "\n")
}
