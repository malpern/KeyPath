import ArgumentParser
import Foundation
import KeyPathCore

struct Uninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove KeyPath for this user (backs up first; needs --yes)",
        discussion: """
        Runs KeyPath.app's own uninstall: stops remapping and restores keyboard mappings \
        it owns, backs up rules and settings to ~/Downloads/KeyPath-Uninstall-Backup-…, \
        removes its data and moves the app to the Trash.
        Without --yes it shows the plan and exits 2 with nothing changed.
        --reset-permissions also clears KeyPath's Accessibility and Input Monitoring entries.
        Exit codes: 0 removed, 1 refused or failed (nothing removed unless stated), 2 needs --yes, \
        6 KeyPath.app could not be reached.
        """
    )

    static let bundleID = "com.keypath.KeyPath"

    private struct Plan: Encodable {
        let applied: Bool
        let plan: [String]
    }

    @OptionGroup var globals: GlobalOptions

    @Flag(help: "Actually uninstall")
    var yes = false

    @Flag(name: .customLong("reset-permissions"), help: "Also clear KeyPath's macOS permission entries")
    var resetPermissions = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let plan = [
            "Stop remapping and restore keyboard mappings KeyPath owns",
            "Back up rules and settings to ~/Downloads/KeyPath-Uninstall-Backup-…",
            "Remove ~/.config/keypath, ~/Library/Application Support/KeyPath, its caches and preferences",
            "Turn off Launch at Login and move \(RuntimeControlClient.appURL.path) to the Trash",
        ] + (resetPermissions ? ["Clear KeyPath's Accessibility and Input Monitoring entries"] : [])
        guard yes, !globals.dryRun else {
            CLIOutput.write(Plan(applied: false, plan: plan), context: ctx) {
                (["Uninstall would:"] + plan.map { "  - \($0)" } + ["", "Nothing changed. Re-run with --yes to uninstall."])
                    .joined(separator: "\n")
            }
            throw ExitCode(2)
        }
        // tccutil finds the app by bundle id, which fails once the app is in the
        // Trash, so clear the entries while it is still installed.
        var reset: [String] = []
        if resetPermissions {
            for service in ["Accessibility", "ListenEvent", "PostEvent"] {
                let tcc = Process()
                tcc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                tcc.arguments = ["reset", service, Self.bundleID]
                tcc.standardOutput = FileHandle.nullDevice
                tcc.standardError = FileHandle.nullDevice
                if (try? tcc.run()) != nil {
                    tcc.waitUntilExit()
                    if tcc.terminationStatus == 0 { reset.append(service) }
                }
            }
        }
        let response: RuntimeControl.Response
        do {
            response = try RuntimeControlClient.sendLaunching(.uninstall, timeout: max(globals.timeout, 120),
                                                              ctx: ctx, confirmed: true)
        } catch {
            let failure = RuntimeControlClient.appUnreachable(error, action: "uninstall")
            CLIOutput.writeError(failure, context: ctx)
            throw failure.code.exitCode
        }
        CLIOutput.write(response, context: ctx) {
            var lines = [response.ok ? "KeyPath was uninstalled." : "KeyPath was not uninstalled."]
            if let message = response.message { lines.append(message) }
            if resetPermissions {
                lines.append(reset.count == 3 ? "Permission entries cleared."
                    : "Some permission entries could not be cleared; remove KeyPath in System Settings > Privacy & Security.")
            }
            return lines.joined(separator: "\n")
        }
        if !response.ok { throw ExitCode.failure }
    }
}
