import AppKit
import ArgumentParser
import Foundation
import KeyPathCore

/// Talks to the running KeyPath app over `RuntimeControl`. The app owns the
/// driverless runtime, so status and lifecycle commands ask it rather than
/// inspecting processes from outside.
enum RuntimeControlClient {
    /// Exit codes for the runtime commands (also listed in guides/cli.md):
    /// 0 done / running, 1 not running or the operation failed,
    /// 6 KeyPath.app is not running or did not answer.
    static let notRunningExit = ExitCode.failure

    static func send(_ operation: RuntimeControl.Operation, timeout: Int) throws -> RuntimeControl.Response {
        try RuntimeControl.send(.init(operation: operation), timeout: TimeInterval(timeout))
    }

    /// The app that contains this CLI, else the installed one.
    static var appURL: URL {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if bundle.pathExtension == "app" { return bundle }
        return URL(fileURLWithPath: "/Applications/KeyPath.app")
    }

    /// Launch KeyPath in the background and wait until it answers.
    static func launchApp(timeout: Int) throws {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-a", appURL.path]
        try open.run()
        open.waitUntilExit()
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while Date() < deadline {
            if (try? send(.status, timeout: 2)) != nil { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw RuntimeControl.ClientError.appNotRunning
    }

    static func appUnreachable(_ error: Error, action: String) -> CLIError {
        let message: String
        let hint: String
        switch error as? RuntimeControl.ClientError {
        case .appNotRunning?:
            message = "KeyPath.app is not running"
            hint = action == "status" ? "Run 'keypath start' to launch it and start remapping" : "Open KeyPath.app, then retry"
        case .timedOut?:
            message = "KeyPath.app did not answer in time"
            hint = "Retry with a longer --timeout, or check 'keypath logs'"
        default:
            message = "Could not talk to KeyPath.app: \(error)"
            hint = "Check 'keypath logs'"
        }
        return CLIError(code: .serviceUnreachable, message: message, hint: hint, details: nil, docsUrl: nil)
    }

    static func humanStatus(_ response: RuntimeControl.Response, noColor: Bool) -> String {
        let mark: String = switch response.state {
        case .running: ANSIColor.green("●", noColor: noColor)
        case .starting: ANSIColor.yellow("●", noColor: noColor)
        default: ANSIColor.red("●", noColor: noColor)
        }
        var lines = ["\(mark) Remapping: \(label(response.state))"]
        if let layer = response.layer, response.state == .running { lines.append("  Layer: \(layer)") }
        if let failure = response.failure { lines.append("  Reason: \(failure)") }
        if let error = response.lastError, error != response.failure { lines.append("  Last error: \(error)") }
        lines.append("  KeyPath \(response.appVersion) (pid \(response.appPID))")
        return lines.joined(separator: "\n")
    }

    static func label(_ state: RuntimeControl.State) -> String {
        switch state {
        case .running: "running"
        case .starting: "starting"
        case .stopped: "stopped"
        case .failed: "not running"
        case .unknown: "unknown"
        }
    }

    /// Shared body of start/stop/restart.
    static func run(_ operation: RuntimeControl.Operation, globals: GlobalOptions, launch: Bool) throws {
        let ctx = globals.outputContext
        var response: RuntimeControl.Response
        do {
            response = try send(operation, timeout: globals.timeout)
        } catch RuntimeControl.ClientError.appNotRunning where operation == .stop {
            CLIOutput.write(["stopped": true], context: ctx) { "KeyPath.app is not running, so remapping is already off." }
            return
        } catch RuntimeControl.ClientError.appNotRunning where launch {
            CLIOutput.progress("Launching KeyPath.app...", context: ctx)
            do {
                try launchApp(timeout: globals.timeout)
                response = try send(operation == .restart ? .start : operation, timeout: globals.timeout)
            } catch {
                let failure = appUnreachable(error, action: operation.rawValue)
                CLIOutput.writeError(failure, context: ctx)
                throw failure.code.exitCode
            }
        } catch {
            let failure = appUnreachable(error, action: operation.rawValue)
            CLIOutput.writeError(failure, context: ctx)
            throw failure.code.exitCode
        }

        let succeeded = response.ok && (operation == .stop ? response.state != .running : response.state == .running)
        CLIOutput.write(response, context: ctx) {
            let verb = switch operation {
            case .start: succeeded ? "Remapping started." : "Remapping did not start."
            case .stop: succeeded ? "Remapping stopped." : "Remapping did not stop."
            case .restart: succeeded ? "Remapping restarted." : "Remapping did not restart."
            case .status: ""
            }
            return verb + "\n" + humanStatus(response, noColor: ctx.noColor)
        }
        if !succeeded { throw notRunningExit }
    }
}
