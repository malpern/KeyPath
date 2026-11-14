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
        --reset-permissions also clears KeyPath's macOS privacy permission entries.
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
        ] + (resetPermissions ? ["Clear KeyPath's macOS privacy permission entries (\(AccessibilityPermissionPresentation.current.name) and event access)"] : [])
        guard yes, !globals.dryRun else {
            CLIOutput.write(Plan(applied: false, plan: plan), context: ctx) {
                (["Uninstall would:"] + plan.map { "  - \($0)" } + ["", "Nothing changed. Re-run with --yes to uninstall."])
                    .joined(separator: "\n")
            }
            throw ExitCode(2)
        }
        let response: RuntimeControl.Response
        do {
            // KeyPath asks on screen first. It clears the permission entries
            // itself, after the person confirms and while it is still installed.
            CLIOutput.progress("Confirm the uninstall in KeyPath's dialog...", context: ctx)
            response = try RuntimeControlClient.sendLaunching(
                .uninstall, timeout: max(globals.timeout, 120), ctx: ctx, confirmed: true,
                argument: resetPermissions ? RuntimeControl.Request.resetPermissionsArgument : nil
            )
        } catch {
            let failure = RuntimeControlClient.appUnreachable(error, action: "uninstall")
            CLIOutput.writeError(failure, context: ctx)
            throw failure.code.exitCode
        }
        CLIOutput.write(response, context: ctx) {
            var lines = [response.ok ? "KeyPath was uninstalled." : "KeyPath was not uninstalled."]
            // The app reports the permission reset in its message.
            if let message = response.message { lines.append(message) }
            return lines.joined(separator: "\n")
        }
        if !response.ok { throw ExitCode.failure }
    }
}
