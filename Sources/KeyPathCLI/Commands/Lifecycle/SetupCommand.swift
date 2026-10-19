import AppKit
import ArgumentParser
import Foundation
import KeyPathCore

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Get KeyPath working: repair, ask for permissions, start remapping",
        discussion: """
        Launches KeyPath.app if needed and runs its own repair. When a macOS permission \
        is missing, opens that pane in System Settings and waits for you to turn it on \
        (macOS lets only a person do that), then starts remapping.
        Exit codes: 0 ready, 7 a permission is still off after --wait, 1 another problem, \
        6 KeyPath.app could not be reached.
        """,
        aliases: ["repair"]
    )

    @OptionGroup var globals: GlobalOptions

    @Option(help: "Seconds to wait for you to grant a permission (default: 300)")
    var wait: Int = 300

    @Flag(name: .customLong("no-open"), help: "Do not open System Settings; just report what is needed")
    var noOpen = false

    mutating func run() async throws {
        let ctx = globals.outputContext
        let timeout = max(globals.timeout, 120)
        var response: RuntimeControl.Response
        do {
            CLIOutput.progress("Repairing...", context: ctx)
            response = try RuntimeControlClient.sendLaunching(.repair, timeout: timeout, ctx: ctx)
            var opened = Set<String>()
            let deadline = Date().addingTimeInterval(TimeInterval(wait))
            // Only the user can flip a permission switch: open the pane once, then wait.
            while response.ready != true, let pending = response.issues?.filter(\.needsUser), !pending.isEmpty,
                  Date() < deadline
            {
                for issue in pending where !opened.contains(issue.title) {
                    opened.insert(issue.title)
                    CLIOutput.progress("Needs you: \(issue.title). \(issue.fix)", context: ctx)
                    if !noOpen, let raw = issue.settingsURL, let url = URL(string: raw) { NSWorkspace.shared.open(url) }
                }
                if noOpen { break }
                try? await Task.sleep(for: .seconds(2))
                response = try RuntimeControlClient.send(.doctor, timeout: 30)
                if response.issues?.contains(where: \.needsUser) == false, response.ready != true {
                    // Permission granted: try again now that nothing needs the user.
                    response = try RuntimeControlClient.send(.repair, timeout: timeout)
                }
            }
        } catch {
            let failure = RuntimeControlClient.appUnreachable(error, action: "setup")
            CLIOutput.writeError(failure, context: ctx)
            throw failure.code.exitCode
        }
        let final = response
        CLIOutput.write(final, context: ctx) {
            let headline = final.ready == true ? "KeyPath is set up and remapping." : "KeyPath is not ready yet."
            return [headline, RuntimeControlClient.humanStatus(final, noColor: ctx.noColor),
                    RuntimeControlClient.humanIssues(final, noColor: ctx.noColor), final.message ?? ""]
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        if let exit = RuntimeControlClient.readinessExit(final) { throw exit }
    }
}
