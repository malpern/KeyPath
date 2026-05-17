import Foundation
import KeyPathAppKit

public struct OutputContext: Sendable {
    public let isInteractive: Bool
    public let forceJSON: Bool
    public let forceHuman: Bool
    public let noColor: Bool

    public var shouldOutputJSON: Bool { forceJSON || (!forceHuman && !isInteractive) }

    public init(isInteractive: Bool, forceJSON: Bool, forceHuman: Bool, noColor: Bool) {
        self.isInteractive = isInteractive
        self.forceJSON = forceJSON
        self.forceHuman = forceHuman
        self.noColor = noColor
    }

    public static func detect(forceJSON: Bool = false, forceHuman: Bool = false) -> OutputContext {
        OutputContext(
            isInteractive: isatty(STDOUT_FILENO) != 0,
            forceJSON: forceJSON,
            forceHuman: forceHuman,
            noColor: ProcessInfo.processInfo.environment["NO_COLOR"] != nil
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

    static func writeJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else {
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
            printErr("Error: \(error.message)")
            if let hint = error.hint {
                printErr("Hint: \(hint)")
            }
            if let details = error.details {
                for detail in details {
                    printErr("  \(detail)")
                }
            }
        }
    }

    static func progress(_ message: String, context: OutputContext) {
        guard context.isInteractive else { return }
        printErr(message)
    }
}
