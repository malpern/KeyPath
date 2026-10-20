import ArgumentParser
import Foundation
import KeyPathCore

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check everything KeyPath needs, with the fix for anything missing",
        discussion: """
        Asks the running KeyPath.app, so permissions and the runtime are checked from \
        the process that uses them. Changes nothing.
        Exit codes: 0 ready, 7 a macOS permission needs you, 1 another problem, \
        6 KeyPath.app is not running (run 'keypath setup').
        """
    )

    @OptionGroup var globals: GlobalOptions

    mutating func run() async throws {
        let ctx = globals.outputContext
        let response: RuntimeControl.Response
        do {
            response = try RuntimeControlClient.send(.doctor, timeout: max(globals.timeout, 30))
        } catch {
            let failure = RuntimeControlClient.appUnreachable(error, action: "doctor")
            CLIOutput.writeError(failure, context: ctx)
            throw failure.code.exitCode
        }
        CLIOutput.write(response, context: ctx) {
            [RuntimeControlClient.humanStatus(response, noColor: ctx.noColor),
             RuntimeControlClient.humanIssues(response, noColor: ctx.noColor),
             RuntimeControlClient.humanAdmission(response, noColor: ctx.noColor)]
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        if let exit = RuntimeControlClient.readinessExit(response) { throw exit }
    }
}
