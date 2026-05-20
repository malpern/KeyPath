import Foundation
import KeyPathAppKit

public struct OutputContext: Sendable {
    public let isInteractive: Bool
    public let forceJSON: Bool
    public let forceHuman: Bool
    public let noColor: Bool
    public let quiet: Bool

    public var shouldOutputJSON: Bool { forceJSON || (!forceHuman && !isInteractive) }

    public init(isInteractive: Bool, forceJSON: Bool, forceHuman: Bool, noColor: Bool, quiet: Bool = false) {
        self.isInteractive = isInteractive
        self.forceJSON = forceJSON
        self.forceHuman = forceHuman
        self.noColor = noColor
        self.quiet = quiet
    }

    public static func detect(forceJSON: Bool = false, forceHuman: Bool = false, quiet: Bool = false) -> OutputContext {
        OutputContext(
            isInteractive: isatty(STDOUT_FILENO) != 0,
            forceJSON: forceJSON,
            forceHuman: forceHuman,
            noColor: ProcessInfo.processInfo.environment["NO_COLOR"] != nil,
            quiet: quiet
        )
    }
}

enum CLIOutput {
    static func write<T: Encodable>(_ value: T, context: OutputContext, humanRender: () -> String) {
        if context.shouldOutputJSON {
            writeJSON(value)
        } else {
            let text = humanRender()
            print(text)
        }
    }

    private struct APIEnvelope<T: Encodable>: Encodable {
        let apiVersion: Int = 1
        let data: T
    }

    static func writeJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let envelope = APIEnvelope(data: value)
        guard let data = try? encoder.encode(envelope), let json = String(data: data, encoding: .utf8) else {
            return
        }
        print(json)
    }

    static func writeError(_ error: CLIError, context: OutputContext) {
        if context.shouldOutputJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(error), let json = String(data: data, encoding: .utf8) {
                printErr(json)
            }
        } else {
            let nc = context.noColor
            printErr(ANSIColor.red("Error: \(error.message)", noColor: nc))
            if let hint = error.hint {
                printErr(ANSIColor.dim("Hint: \(hint)", noColor: nc))
            }
            if let details = error.details {
                for detail in details {
                    printErr(ANSIColor.dim("  \(detail)", noColor: nc))
                }
            }
            if let docsUrl = error.docsUrl {
                printErr(ANSIColor.dim("Docs: \(docsUrl)", noColor: nc))
            }
        }
    }

    static func progress(_ message: String, context: OutputContext) {
        guard context.isInteractive, !context.quiet else { return }
        printErr(ANSIColor.yellow(message, noColor: context.noColor))
    }
}
